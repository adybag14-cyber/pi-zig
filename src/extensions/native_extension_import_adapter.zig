//! Experimental Source48/39 extension import adapter. Real filesystem bytes,
//! native TS transform, shared native namespaces and exact private C origins.
//! Context-pinned records are charged; no default path installs this adapter.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const js = @import("native_js_values.zig");
const v = @import("native_ai_provider_values.zig");
const body = @import("native_async_body.zig");
const af = body.native;
const charged = @import("native_env_charged_allocator.zig");
const ts = @import("typescript.zig");
pub const Kind = enum { transformed_ts, shared_esm, shared_commonjs, shared_json, shared_value };
pub const Namespace = struct { specifier: []const u8, canonical_name: []const u8, exports_authority: c.JSValue };
pub const Inputs = struct { io: std.Io, namespaces: []const Namespace };
pub const Session = opaque {};
const Binding = struct { specifier: []u8, canonical_name: []u8, authority: c.JSValue };
const Entry = struct { next: ?*Entry, path: []u8, kind: Kind };
const Hub = struct {
    engine: *em.Engine,
    allocator_owner: charged.ChargedAllocator,
    class_id: c.JSClassID,
    sessions: ?*SessionRecord = null,
    shared: ?*Entry = null,
    shutting_down: bool = false,
    fn allocator(self: *Hub) std.mem.Allocator { return self.allocator_owner.allocator(); }
};
const SessionRecord = struct {
    next: ?*SessionRecord,
    hub: *Hub,
    io: std.Io,
    loader: em.SourceLoader,
    bindings: []Binding,
    handle: c.JSValue,
    graph: ?*c.JSPiPrivateModuleGraph = null,
    private: ?*Entry = null,
    started: bool = false,
};
const names = [_]struct { name: []const u8, group: u8 }{
    .{ .name = "typebox", .group = 0 }, .{ .name = "@sinclair/typebox", .group = 0 },
    .{ .name = "typebox/compile", .group = 1 }, .{ .name = "@sinclair/typebox/compile", .group = 1 },
    .{ .name = "typebox/value", .group = 2 }, .{ .name = "@sinclair/typebox/value", .group = 2 },
    .{ .name = "@earendil-works/pi-agent-core", .group = 3 }, .{ .name = "@mariozechner/pi-agent-core", .group = 3 },
    .{ .name = "@earendil-works/pi-tui", .group = 4 }, .{ .name = "@mariozechner/pi-tui", .group = 4 },
    .{ .name = "@earendil-works/pi-ai", .group = 5 }, .{ .name = "@earendil-works/pi-ai/compat", .group = 5 },
    .{ .name = "@mariozechner/pi-ai", .group = 5 }, .{ .name = "@mariozechner/pi-ai/compat", .group = 5 },
    .{ .name = "@earendil-works/pi-ai/oauth", .group = 6 }, .{ .name = "@mariozechner/pi-ai/oauth", .group = 6 },
    .{ .name = "@earendil-works/pi-ai/providers/all", .group = 7 }, .{ .name = "@mariozechner/pi-ai/providers/all", .group = 7 },
    .{ .name = "@earendil-works/pi-coding-agent", .group = 8 }, .{ .name = "@mariozechner/pi-coding-agent", .group = 8 },
};
fn hub(engine: *em.Engine) !*Hub {
    if (engine.native_extension_import_context) |raw| return @ptrCast(@alignCast(raw));
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Hub)) == 0) return error.OutOfMemory;
    errdefer c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Hub));
    const result = try engine.gpa.create(Hub);
    errdefer engine.gpa.destroy(result);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "PrivateExtensionImportSession", .finalizer = null, .gc_mark = null, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    result.* = .{ .engine = engine, .allocator_owner = charged.ChargedAllocator.init(engine), .class_id = id };
    engine.native_extension_import_context = result;
    return result;
}
pub fn createSession(engine: *em.Engine, inputs: Inputs) !*Session {
    if (inputs.namespaces.len != names.len) return error.RequiredActualExtensionVirtualNamespaces;
    const captured_loader = engine.source_loader orelse return error.NativeModuleLoaderUnavailable;
    if (captured_loader.normalize == null or captured_loader.input == null) return error.RequiredActualExtensionSourceLoader;
    const owner = try hub(engine);
    if (owner.shutting_down) return error.ExtensionImporterShuttingDown;
    const allocator = owner.allocator();
    const bindings = try allocator.alloc(Binding, names.len);
    var initialized: usize = 0;
    errdefer {
        for (bindings[0..initialized]) |binding| { allocator.free(binding.specifier); allocator.free(binding.canonical_name); engine.freeValue(binding.authority); }
        allocator.free(bindings);
    }
    for (names, 0..) |expected, index| {
        var found: ?Namespace = null;
        for (inputs.namespaces) |supplied| if (std.mem.eql(u8, supplied.specifier, expected.name)) {
            if (found != null) return error.DuplicateExtensionVirtualNamespace;
            found = supplied;
        };
        const supplied = found orelse return error.RequiredActualExtensionVirtualNamespaces;
        if (!engine.native_module_names.contains(supplied.canonical_name)) return error.RequiredRegisteredExtensionNamespace;
        const actual = engine.native_module_values.get(supplied.canonical_name) orelse return error.RequiredRegisteredExtensionNamespace;
        if (!c.JS_IsObject(actual) or !c.JS_IsStrictEqual(engine.context, actual, supplied.exports_authority)) return error.ExtensionNamespaceAuthorityMismatch;
        for (names[0..index], 0..) |earlier, previous| if (earlier.group == expected.group) {
            if (!std.mem.eql(u8, bindings[previous].canonical_name, supplied.canonical_name)) return error.ExtensionAliasRequiresCanonicalModuleIdentity;
        };
        const specifier = try allocator.dupe(u8, supplied.specifier);
        errdefer allocator.free(specifier);
        const canonical = try allocator.dupe(u8, supplied.canonical_name);
        bindings[index] = .{ .specifier = specifier, .canonical_name = canonical, .authority = c.JS_DupValue(engine.context, actual) };
        initialized += 1;
    }
    const session = try allocator.create(SessionRecord);
    errdefer allocator.destroy(session);
    const handle = try engine.checked(c.JS_NewObjectClass(engine.context, owner.class_id));
    session.* = .{ .next = owner.sessions, .hub = owner, .io = inputs.io, .loader = captured_loader, .bindings = bindings, .handle = handle };
    _ = c.JS_SetOpaque(handle, session);
    owner.sessions = session;
    return @ptrCast(session);
}
fn admitted(engine: *em.Engine, pointer: *const anyopaque) ?*SessionRecord {
    const raw = engine.native_extension_import_context orelse return null;
    const owner: *Hub = @ptrCast(@alignCast(raw));
    var cursor = owner.sessions;
    if (owner.shutting_down) return null;
    while (cursor) |item| : (cursor = item.next) if (@intFromPtr(item) == @intFromPtr(pointer)) return item;
    return null;
}
fn checkLoader(session: *SessionRecord) !void {
    if (session.hub.shutting_down) return error.ExtensionImporterShuttingDown;
    const current = session.hub.engine.source_loader orelse return error.ExtensionSourceLoaderReconfigured;
    const captured = session.loader;
    if (current.context != captured.context or current.load != captured.load or current.input != captured.input or current.normalize != captured.normalize or current.normalize_require != captured.normalize_require) return error.ExtensionSourceLoaderReconfigured;
}
fn bindingName(session: *SessionRecord, specifier: []const u8) ?[]const u8 {
    for (session.bindings) |binding| if (std.mem.eql(u8, binding.specifier, specifier)) return binding.canonical_name;
    return null;
}
fn normalized(session: *SessionRecord, base: []const u8, specifier: []const u8) ![]u8 {
    try checkLoader(session);
    const allocator = session.hub.allocator();
    if (bindingName(session, specifier)) |canonical| return allocator.dupe(u8, canonical);
    const engine = session.hub.engine;
    if (std.mem.startsWith(u8, specifier, "node:")) {
        if (!engine.native_module_names.contains(specifier)) return error.RequiredActualNodeNamespace;
        return allocator.dupe(u8, specifier);
    }
    const node_name = try std.fmt.allocPrint(allocator, "node:{s}", .{specifier});
    defer allocator.free(node_name);
    if (engine.native_module_names.contains(node_name)) return allocator.dupe(u8, node_name);
    if (!std.fs.path.isAbsolute(specifier) and !std.mem.startsWith(u8, specifier, "./") and !std.mem.startsWith(u8, specifier, "../") and !std.ascii.startsWithIgnoreCase(specifier, "file:")) return error.UnobservedExtensionBareSpecifierPolicy;
    return session.loader.normalize.?(session.loader.context, allocator, base, specifier);
}
fn find(head: ?*Entry, path: []const u8) ?*Entry {
    var cursor = head;
    while (cursor) |entry| : (cursor = entry.next) if (std.mem.eql(u8, entry.path, path)) return entry;
    return null;
}
fn remember(session: *SessionRecord, path: []const u8, kind: Kind) !void {
    const allocator = session.hub.allocator();
    const entry = try allocator.create(Entry);
    errdefer allocator.destroy(entry);
    const owned = try allocator.dupe(u8, path);
    const head = if (kind == .transformed_ts) &session.private else &session.hub.shared;
    entry.* = .{ .next = head.*, .path = owned, .kind = kind };
    head.* = entry;
}
fn sourceBytes(session: *SessionRecord, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(session.io, path, session.hub.allocator(), .limited(16 * 1024 * 1024));
}
fn classifyJavaScript(session: *SessionRecord, path: []const u8) !Kind {
    const allocator = session.hub.allocator();
    var directory = std.fs.path.dirname(path) orelse return error.InvalidExtensionPhysicalPath;
    while (true) {
        const package_path = try std.fs.path.join(allocator, &.{directory, "package.json"});
        defer allocator.free(package_path);
        const bytes = std.Io.Dir.cwd().readFileAlloc(session.io, package_path, allocator, .limited(1024 * 1024)) catch |err| switch (err) { error.FileNotFound, error.NotDir => null, else => return err };
        if (bytes) |content| {
            defer allocator.free(content);
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidExtensionPackage;
            if (parsed.value.object.get("type")) |kind| {
                if (kind != .string) return error.InvalidExtensionPackage;
                if (std.mem.eql(u8, kind.string, "module")) return .shared_esm;
                if (std.mem.eql(u8, kind.string, "commonjs")) return .shared_commonjs;
                return error.UnobservedExtensionPackageType;
            }
            break;
        }
        if (std.mem.eql(u8, std.fs.path.basename(directory), "node_modules")) break;
        const parent = std.fs.path.dirname(directory) orelse break;
        if (std.mem.eql(u8, parent, directory)) break;
        directory = parent;
    }
    const bytes = try sourceBytes(session, path);
    defer allocator.free(bytes);
    if (try ts.hasModuleSyntax(bytes)) return error.UnobservedNoTypeJavaScriptEsmPolicy;
    return .shared_commonjs;
}
fn kindOf(session: *SessionRecord, path: []const u8) !Kind {
    try checkLoader(session);
    if (session.hub.engine.native_module_names.contains(path)) return .shared_value;
    if (find(session.hub.shared, path)) |entry| return entry.kind;
    if (find(session.private, path)) |entry| return entry.kind;
    const extension = std.fs.path.extension(path);
    const kind: Kind = if (std.mem.eql(u8, extension, ".ts")) typed: {
        if (std.mem.indexOf(u8, path, "/node_modules/") != null or std.mem.indexOf(u8, path, "\\node_modules\\") != null) return error.UnobservedNativePackageTypeScriptPolicy;
        break :typed .transformed_ts;
    } else if (std.mem.eql(u8, extension, ".mjs")) .shared_esm
    else if (std.mem.eql(u8, extension, ".cjs")) .shared_commonjs
    else if (std.mem.eql(u8, extension, ".json")) .shared_json
    else if (std.mem.eql(u8, extension, ".js")) try classifyJavaScript(session, path)
    else return error.UnobservedExtensionModuleKind;
    try remember(session, path, kind);
    return kind;
}
fn callbackFailure(engine: *em.Engine, err: anyerror, generation: u64) void {
    if (err == error.JavaScriptException) {
        if (engine.captured_exception) |reason| if (!c.JS_IsUncatchableError(reason)) {
            body.rethrowRecognizedAllocation(engine, reason, generation) catch {};
        };
        _ = engine.throwCaptured(); return;
    }
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemory();
        const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason);
        _ = c.JS_Throw(engine.context, reason); return;
    }
    _ = c.JS_ThrowTypeError(engine.context, "Native extension import: %s", @as([*:0]const u8, @errorName(err)));
}
fn fromOpaque(raw: ?*anyopaque) *SessionRecord { return @ptrCast(@alignCast(raw.?)); }
fn normalizeGraph(context: ?*c.JSContext, origin: ?*const c.JSPiModuleOrigin, base: [*c]const u8, specifier: [*c]const u8, attrs: c.JSValue, raw: ?*anyopaque) callconv(.c) [*c]u8 {
    const session = fromOpaque(raw);
    session.hub.engine.native_exception_diagnostics_suppressed += 1;
    defer session.hub.engine.native_exception_diagnostics_suppressed -= 1;
    const generation = session.hub.engine.native_allocation_generation;
    if (context != session.hub.engine.context or c.JS_PiModuleOriginGraph(origin) != session.graph or !c.JS_IsUndefined(attrs)) {
        callbackFailure(session.hub.engine, error.UnobservedExtensionImportOriginOrAttributes, generation); return null;
    }
    if (!std.mem.eql(u8, std.mem.span(c.JS_PiModuleOriginFilename(origin)), std.mem.span(base))) {
        callbackFailure(session.hub.engine, error.ExtensionPhysicalOriginMismatch, generation); return null;
    }
    const name = normalized(session, std.mem.span(base), std.mem.span(specifier)) catch |err| { callbackFailure(session.hub.engine, err, generation); return null; };
    defer session.hub.allocator().free(name);
    const allocation = c.js_malloc(context, name.len + 1) orelse {
        // This allocation just failed at the current trusted boundary. Preserve
        // its exact VM reason; do not classify a historical name/lookalike.
        if (c.JS_HasException(context)) {
            const reason = c.JS_GetException(context);
            c.JS_SetUncatchableError(context, reason);
            _ = c.JS_Throw(context, reason);
        }
        return null;
    };
    const output: [*]u8 = @ptrCast(allocation);
    @memcpy(output[0..name.len], name); output[name.len] = 0;
    return output;
}
fn selectGraph(context: ?*c.JSContext, origin: ?*const c.JSPiModuleOrigin, name: [*c]const u8, attrs: c.JSValue, raw: ?*anyopaque) callconv(.c) c_int {
    const session = fromOpaque(raw);
    session.hub.engine.native_exception_diagnostics_suppressed += 1;
    defer session.hub.engine.native_exception_diagnostics_suppressed -= 1;
    const generation = session.hub.engine.native_allocation_generation;
    if (context != session.hub.engine.context or c.JS_PiModuleOriginGraph(origin) != session.graph or !c.JS_IsUndefined(attrs)) {
        callbackFailure(session.hub.engine, error.UnobservedExtensionImportOriginOrAttributes, generation); return -1;
    }
    const kind = kindOf(session, std.mem.span(name)) catch |err| { callbackFailure(session.hub.engine, err, generation); return -1; };
    return if (kind == .transformed_ts) 1 else 0;
}
fn compilePrivate(session: *SessionRecord, graph: *c.JSPiPrivateModuleGraph, name: [:0]const u8, attrs: c.JSValue) !c.JSValue {
    if (try kindOf(session, name) != .transformed_ts) return error.PrivateExtensionKindMismatch;
    const allocator = session.hub.allocator();
    const bytes = try sourceBytes(session, name); defer allocator.free(bytes);
    const transformed = try ts.transform(allocator, bytes); defer allocator.free(transformed);
    const terminated = try allocator.dupeZ(u8, transformed); defer allocator.free(terminated);
    const engine = session.hub.engine;
    const compiled = try engine.checked(c.JS_PiCompilePrivateModule(engine.context, graph, terminated.ptr, terminated.len, name.ptr, attrs));
    errdefer engine.freeValue(compiled);
    try engine.initializeExtensionImportMeta(c.pi_js_module(compiled).?, name);
    return compiled;
}
fn loadGraph(context: ?*c.JSContext, graph: ?*c.JSPiPrivateModuleGraph, name: [*c]const u8, attrs: c.JSValue, raw: ?*anyopaque) callconv(.c) ?*c.JSModuleDef {
    const session = fromOpaque(raw);
    session.hub.engine.native_exception_diagnostics_suppressed += 1;
    defer session.hub.engine.native_exception_diagnostics_suppressed -= 1;
    const generation = session.hub.engine.native_allocation_generation;
    if (context != session.hub.engine.context or graph == null or graph != session.graph or !c.JS_IsUndefined(attrs)) {
        callbackFailure(session.hub.engine, error.UnobservedExtensionImportOriginOrAttributes, generation); return null;
    }
    const terminated: [*:0]const u8 = @ptrCast(name);
    const compiled = compilePrivate(session, graph.?, std.mem.span(terminated), attrs) catch |err| { callbackFailure(session.hub.engine, err, generation); return null; };
    defer session.hub.engine.freeValue(compiled);
    return c.pi_js_module(compiled);
}
pub fn start(engine: *em.Engine, public_session: *Session, base: []const u8, specifier: []const u8, attributes: c.JSValue) !c.JSValue {
    const session = admitted(engine, public_session) orelse return error.InvalidExtensionImportSession;
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    const function = try scope.own(try af.createResumable(engine, "importExtensionModule", 0, importBody, &.{session.handle, try scope.text(base), try scope.text(specifier), attributes}));
    return engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null));
}
fn importBody(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const generation = engine.native_allocation_generation;
    return importInner(engine, roots, state, completion, input) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
            if (c.JS_IsUncatchableError(reason)) return err;
            try body.rethrowRecognizedAllocation(engine, reason, generation);
        };
        return body.failureSince(engine, err, generation);
    };
}
fn importInner(engine: *em.Engine, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    const raw_owner = engine.native_extension_import_context orelse return error.InvalidExtensionImportSession;
    const owner: *Hub = @ptrCast(@alignCast(raw_owner));
    const raw_session = c.JS_GetOpaque(roots[0], owner.class_id) orelse return error.InvalidExtensionImportSession;
    const session = admitted(engine, raw_session) orelse return error.InvalidExtensionImportSession;
    if (completion == .start) {
        if (session.started) return error.ExtensionImportSessionAlreadyStarted;
        session.started = true;
        if (!c.JS_IsUndefined(roots[3])) return error.UnobservedExtensionImportAttributes;
        const job = try body.init(&scope, state);
        try scope.put(job, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
        const base = try engine.toString(roots[1]); defer engine.gpa.free(base);
        const specifier = try engine.toString(roots[2]); defer engine.gpa.free(specifier);
        const name = try normalized(session, base, specifier); defer owner.allocator().free(name);
        const terminated = try owner.allocator().dupeZ(u8, name); defer owner.allocator().free(terminated);
        if (try kindOf(session, name) == .transformed_ts) {
            const graph = c.JS_PiNewPrivateModuleGraph2(engine.context, normalizeGraph, selectGraph, loadGraph, session) orelse return js.capture(engine);
            session.graph = graph;
            const compiled = try scope.own(try compilePrivate(session, graph, terminated, c.pi_js_undefined()));
            try scope.put(job, "module", compiled);
            try scope.put(job, "shared", c.pi_js_bool(engine.context, 0));
            return .{ .awaited = try engine.checked(c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, compiled))) };
        }
        try scope.put(job, "shared", c.pi_js_bool(engine.context, 1));
        const base_z = try owner.allocator().dupeZ(u8, base); defer owner.allocator().free(base_z);
        return .{ .awaited = try engine.checked(c.JS_LoadModule(engine.context, base_z.ptr, terminated.ptr)) };
    }
    const job = state.*;
    if (completion == .rejected) {
        if (c.JS_IsUncatchableError(input)) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, input)));
            unreachable;
        }
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(job, "generation")) < 0) return js.capture(engine);
        try body.rethrowRecognizedAllocation(engine, input, generation);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    if (scope.truthy(try scope.get(job, "shared"))) return .{ .returned = c.JS_DupValue(engine.context, input) };
    const module = c.pi_js_module(try scope.get(job, "module")) orelse return error.InvalidExtensionPrivateModule;
    return .{ .returned = try engine.checked(c.JS_GetModuleNamespace(engine.context, module)) };
}
pub fn prepareShutdown(engine: *em.Engine) void {
    const raw = engine.native_extension_import_context orelse return;
    const owner: *Hub = @ptrCast(@alignCast(raw)); owner.shutting_down = true;
    var cursor = owner.sessions;
    while (cursor) |session| : (cursor = session.next) {
        for (session.bindings) |binding| engine.freeValue(binding.authority);
        engine.freeValue(session.handle);
    }
}
fn freeEntries(allocator: std.mem.Allocator, first: ?*Entry) void {
    var cursor = first;
    while (cursor) |entry| { cursor = entry.next; allocator.free(entry.path); allocator.destroy(entry); }
}
pub fn finishShutdown(engine: *em.Engine) void {
    const raw = engine.native_extension_import_context orelse return;
    const owner: *Hub = @ptrCast(@alignCast(raw));
    const allocator = owner.allocator();
    var cursor = owner.sessions;
    while (cursor) |session| {
        cursor = session.next;
        for (session.bindings) |binding| { allocator.free(binding.specifier); allocator.free(binding.canonical_name); }
        allocator.free(session.bindings); freeEntries(allocator, session.private); allocator.destroy(session);
    }
    freeEntries(allocator, owner.shared);
    owner.allocator_owner.deinit();
    engine.gpa.destroy(owner);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Hub));
    engine.native_extension_import_context = null;
}
