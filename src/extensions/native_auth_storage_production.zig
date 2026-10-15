//! Ordinary Source4954 AuthStorage and InMemoryAuthStorageBackend classes.
//! All Source fields remain ordinary, writable JS properties; callbacks and
//! pending operations retain actual VM values in marked function-data roots.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const funcs = @import("native_node_function.zig");
const class = @import("native_class.zig");
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Method = enum { parseStorageData, updateReadState, reload, reloadFromStorageAsync, readLatestData, read, modify, delete, list };
const Stage = enum(c_int) { adopted, read, list, reload_callback, reload_result, modify_callback, modify_result, delete_result, latest_result, memory_previous, memory_callback };

fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn imported(s: *Scope, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(owner, name), c.pi_js_undefined(), args);
}
fn constructValue(s: *Scope, ctor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, ctor, @intCast(args.len), @constCast(args.ptr))));
}
fn methodValue(s: *Scope, name: [*:0]const u8, length: c_int, callback: funcs.Callback, roots: []const c.JSValue, async_function: bool) !c.JSValue {
    const function = try s.own(try funcs.createMethod(s.engine, name, length, callback, roots));
    if (async_function) {
        const prototype = try s.own(try s.engine.checked(c.JS_GetAsyncFunctionPrototype(s.engine.context)));
        if (c.JS_SetPrototype(s.engine.context, function, prototype) < 0) return v.js.capture(s.engine);
    }
    return function;
}
fn defineMethod(s: *Scope, target: c.JSValue, name: [*:0]const u8, function: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(s.engine.context, target, name, c.JS_DupValue(s.engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(s.engine);
}
fn asyncArrow(s: *Scope, length: c_int, callback: funcs.Callback, roots: []const c.JSValue) !c.JSValue {
    return s.own(try @import("native_ai_auth_helpers.zig").asyncArrow(s.engine, "", length, callback, roots));
}
fn noOp(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    _ = engine;
    return c.pi_js_undefined();
}
fn noop(s: *Scope) !c.JSValue {
    return s.own(try funcs.createArrow(s.engine, "", 0, noOp, &.{}));
}
fn check(s: *Scope, options: c.JSValue) !void {
    const signal = try v.optional(s, options, "signal");
    if (!v.nullish(signal)) _ = try s.invoke(signal, "throwIfAborted", &.{});
}
fn revision(s: *Scope, owner: c.JSValue, self: c.JSValue) !c.JSValue {
    return if (s.truthy(try s.get(self, "authPath"))) imported(s, owner, "getFileRevision", &.{try s.get(self, "authPath")}) else c.pi_js_undefined();
}
fn stringify(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.invoke(try s.global("JSON"), "stringify", &.{ value, c.pi_js_null(), c.JS_NewInt32(s.engine.context, 2) });
}
fn parseStorageData(s: *Scope, content: c.JSValue) !c.JSValue {
    if (!s.truthy(content)) return s.object();
    // Source stripBom delegates to splitBom and the live string methods.
    const json_object = try s.global("JSON");
    const parse = try s.get(json_object, "parse");
    const text = if (s.truthy(try s.invoke(content, "startsWith", &.{try s.text("\xef\xbb\xbf")}))) try s.invoke(content, "slice", &.{c.JS_NewInt32(s.engine.context, 1)}) else content;
    return s.call(parse, json_object, &.{text});
}

/// Mandatory imports are real module bindings, never fabricated default stores:
/// FileAuthStorageBackend (ordinary constructor), getAgentDir, getFileRevision,
/// and resolveConfigValue. NormalizePath reuses the actual native Source body.
/// A module namespace must be created once and retained by the SDK assembler.
pub fn create(engine: *v.em.Engine, imports: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owner = try s.object();
    inline for (.{ "FileAuthStorageBackend", "getAgentDir", "getFileRevision", "resolveConfigValue" }) |name| {
        const binding = try s.get(imports, name);
        if (!c.JS_IsFunction(engine.context, binding)) return error.RequiredActualAuthStorageDependency;
        if (comptime std.mem.eql(u8, name, "FileAuthStorageBackend")) if (!c.JS_IsConstructor(engine.context, binding)) return error.RequiredOrdinaryFileAuthStorageBackend;
        try s.put(owner, name, binding);
    }
    const io = engine.native_io orelse return error.NativeAuthStorageRequiresIo;
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    try s.put(owner, "join", try s.get(engine.native_module_values.get("node:path").?, "join"));
    try s.put(owner, "sharedAuthFileReadState", c.pi_js_undefined());
    const memory_constructor = try s.own(try memoryConstructor(engine, owner));
    try s.put(owner, "InMemoryAuthStorageBackend", memory_constructor);
    const prototype = try s.object();
    const auth_constructor = try s.own(try class.constructor(engine, "AuthStorage", 2, prototype, construct, &.{owner}));
    try s.put(owner, "AuthStorage", auth_constructor);
    inline for (.{ .{ "create", 0 }, .{ "fromStorage", 1 }, .{ "inMemory", 0 } }, 0..) |entry, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return staticCall(host, roots[0], args, index);
            }
        };
        try defineMethod(&s, auth_constructor, entry[0], try methodValue(&s, entry[0], entry[1], Adapter.call, &.{owner}, false));
    }
    inline for (@typeInfo(Method).@"enum".fields) |entry| {
        const method: Method = @enumFromInt(entry.value);
        const Adapter = struct {
            fn call(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return dispatch(host, roots[0], receiver, args, method);
            }
        };
        const length: c_int = switch (method) {
            .reload => 0,
            .updateReadState, .read, .delete => 2,
            .modify => 3,
            else => 1,
        };
        const asynchronous = method != .parseStorageData and method != .updateReadState and method != .reload;
        try defineMethod(&s, prototype, entry.name, try methodValue(&s, entry.name, length, Adapter.call, &.{owner}, asynchronous));
    }
    const exports = try s.object();
    try s.put(exports, "AuthStorage", auth_constructor);
    try s.put(exports, "InMemoryAuthStorageBackend", memory_constructor);
    try s.put(exports, "FileAuthStorageBackend", try s.get(owner, "FileAuthStorageBackend"));
    return c.JS_DupValue(engine.context, exports);
}
/// Genuine standalone composition. The actual config-value resolver remains
/// mandatory; no literal-only or command-skipping substitute is manufactured.
pub fn createDefault(engine: *v.em.Engine, resolve_config_value: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, resolve_config_value)) return error.RequiredActualConfigValueResolver;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const imports = try s.object();
    const get_agent_dir = try s.own(try @import("native_sdk_agent_directory.zig").create(engine, .{}));
    try s.put(imports, "getAgentDir", get_agent_dir);
    try s.put(imports, "FileAuthStorageBackend", try s.own(try @import("native_auth_file_storage_backend.zig").create(engine, .{ .get_agent_dir = get_agent_dir })));
    try @import("native_file_revision.zig").install(engine, imports);
    try s.put(imports, "resolveConfigValue", resolve_config_value);
    return create(engine, imports);
}
pub fn constructor(engine: *v.em.Engine, imports: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const exports = try s.own(try create(engine, imports));
    return c.JS_DupValue(engine.context, try s.get(exports, "AuthStorage"));
}
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owner = roots[0];
    const self = try s.own(try class.object(engine, target));
    inline for (.{ "storage", "authPath", "readState" }) |name| try s.put(self, name, c.pi_js_undefined());
    try s.set(self, "storage", arg(args, 0));
    const path = arg(args, 1);
    try s.set(self, "authPath", path);
    const shared = try s.get(owner, "sharedAuthFileReadState");
    var read_state: c.JSValue = undefined;
    if (s.truthy(path) and s.equal(try v.optional(&s, shared, "authPath"), path)) read_state = try s.get(shared, "readState") else {
        read_state = try s.object();
        try s.put(read_state, "data", try s.object());
    }
    try s.set(self, "readState", read_state);
    if (s.truthy(path) and !s.truthy(shared)) {
        const value = try s.object();
        try s.put(value, "authPath", path);
        try s.put(value, "readState", try s.get(self, "readState"));
        try s.set(owner, "sharedAuthFileReadState", value);
    }
    if (s.truthy(path)) {
        const current_revision = try imported(&s, owner, "getFileRevision", &.{path});
        if (!c.JS_IsUndefined(current_revision) and s.equal(current_revision, try s.get(try s.get(self, "readState"), "revision"))) return c.JS_DupValue(engine.context, self);
    }
    _ = try s.invoke(self, "reload", &.{});
    return c.JS_DupValue(engine.context, self);
}
fn staticCall(engine: *v.em.Engine, owner: c.JSValue, args: []const c.JSValue, kind: usize) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (kind == 0) {
        var path = arg(args, 0);
        if (c.JS_IsUndefined(path)) path = try imported(&s, owner, "join", &.{ try imported(&s, owner, "getAgentDir", &.{}), try s.text("auth.json") });
        const normalized = try s.own(try @import("native_sdk_source_paths.zig").normalize(engine, path, c.pi_js_undefined()));
        const auth_constructor = try s.get(owner, "AuthStorage");
        const backend = try constructValue(&s, try s.get(owner, "FileAuthStorageBackend"), &.{normalized});
        return c.JS_DupValue(engine.context, try constructValue(&s, auth_constructor, &.{ backend, normalized }));
    }
    if (kind == 1) return c.JS_DupValue(engine.context, try constructValue(&s, try s.get(owner, "AuthStorage"), &.{arg(args, 0)}));
    const supplied = arg(args, 0);
    const data = if (c.JS_IsUndefined(supplied)) try s.object() else supplied;
    const storage = try constructValue(&s, try s.get(owner, "InMemoryAuthStorageBackend"), &.{});
    const callback = try asyncInitMemory(&s, data);
    _ = try s.invoke(storage, "withLock", &.{callback});
    return c.JS_DupValue(engine.context, try s.invoke(try s.get(owner, "AuthStorage"), "fromStorage", &.{storage}));
}
fn asyncInitMemory(s: *Scope, data: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const result = try local.object();
            try local.put(result, "result", c.pi_js_undefined());
            try local.put(result, "next", try stringify(&local, roots[0]));
            return c.JS_DupValue(engine.context, result);
        }
    };
    return s.own(try funcs.createArrow(s.engine, "", 0, Adapter.call, &.{data}));
}
fn dispatch(engine: *v.em.Engine, owner: c.JSValue, self: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .parseStorageData) return c.JS_DupValue(engine.context, try parseStorageData(&s, arg(args, 0)));
    if (method == .updateReadState) {
        try s.set(try s.get(self, "readState"), "data", arg(args, 0));
        try s.set(try s.get(self, "readState"), "revision", arg(args, 1));
        return c.pi_js_undefined();
    }
    if (method == .reload) {
        const generation = engine.native_allocation_generation;
        reload(&s, owner, self) catch |err| try @import("native_ai_partial_json.zig").discard(engine, err, generation);
        return c.pi_js_undefined();
    }
    const pending = try flow.create(engine, owner);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try s.put(pending.owner, "self", self);
    const generation = engine.native_allocation_generation;
    try s.put(pending.owner, "generationLow", c.JS_NewInt64(engine.context, @as(u32, @truncate(generation))));
    try s.put(pending.owner, "generationHigh", c.JS_NewInt64(engine.context, @as(u32, @truncate(generation >> 32))));
    try s.put(pending.owner, "options", arg(args, switch (method) {
        .read, .delete => 1,
        .modify => 2,
        else => 0,
    }));
    start(&s, pending.owner, args, method) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn reload(s: *Scope, owner: c.JSValue, self: c.JSValue) !void {
    const job = try s.object();
    try s.put(job, "agent", owner);
    try s.put(job, "self", self);
    const storage = try s.get(self, "storage");
    const lock = try s.get(storage, "withLock");
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            try local.set(roots[0], "content", arg(args, 0));
            try local.set(roots[0], "revision", try revision(&local, try local.get(roots[0], "agent"), try local.get(roots[0], "self")));
            const result = try local.object();
            try local.put(result, "result", c.pi_js_undefined());
            return c.JS_DupValue(engine.context, result);
        }
    };
    const callback = try s.own(try funcs.createArrow(s.engine, "", 1, Adapter.call, &.{job}));
    _ = try s.call(lock, storage, &.{callback});
    const update = try s.get(self, "updateReadState");
    const data = try s.invoke(self, "parseStorageData", &.{try s.get(job, "content")});
    _ = try s.call(update, self, &.{ data, try s.get(job, "revision") });
}
fn start(s: *Scope, job: c.JSValue, args: []const c.JSValue, method: Method) anyerror!void {
    const self = try s.get(job, "self");
    const options = try s.get(job, "options");
    switch (method) {
        .reloadFromStorageAsync => {
            const storage = try s.get(self, "storage");
            const lock = try s.get(storage, "withLockAsync");
            return flow.wait(continued, s.engine, job, try s.call(lock, storage, &.{ try storageCallback(s, job, .reload_callback), options }), @intFromEnum(Stage.adopted));
        },
        .readLatestData => return latest(s, job),
        .read => {
            try s.put(job, "provider", arg(args, 0));
            return flow.wait(continued, s.engine, job, try s.invoke(self, "readLatestData", &.{options}), @intFromEnum(Stage.read));
        },
        .list => {
            const object = try s.global("Object");
            try s.put(job, "Object", object);
            try s.put(job, "entries", try s.get(object, "entries"));
            return flow.wait(continued, s.engine, job, try s.invoke(self, "readLatestData", &.{options}), @intFromEnum(Stage.list));
        },
        .modify, .delete => {
            try s.put(job, "provider", arg(args, 0));
            if (method == .modify) try s.put(job, "fn", arg(args, 1));
            try s.put(job, "latestData", try s.get(try s.get(self, "readState"), "data"));
            const storage = try s.get(self, "storage");
            const lock = try s.get(storage, "withLockAsync");
            return flow.wait(continued, s.engine, job, try s.call(lock, storage, &.{ try storageCallback(s, job, if (method == .modify) .modify_callback else .delete_result), options }), @intFromEnum(if (method == .modify) Stage.modify_result else Stage.delete_result));
        },
        else => unreachable,
    }
}
fn storageCallback(s: *Scope, job: c.JSValue, stage: Stage) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const pending = try flow.create(engine, try local.get(roots[0], "agent"));
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            try local.put(pending.owner, "parent", roots[0]);
            var raw: i32 = 0;
            if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
            callbackStart(&local, pending.owner, arg(args, 0), @enumFromInt(raw)) catch |err| try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        }
    };
    return asyncArrow(s, 1, Adapter.call, &.{ job, c.JS_NewInt32(s.engine.context, @intFromEnum(stage)) });
}
fn callbackStart(s: *Scope, job: c.JSValue, content: c.JSValue, stage: Stage) !void {
    const parent = try s.get(job, "parent");
    const self = try s.get(parent, "self");
    const current_data = try s.invoke(self, "parseStorageData", &.{content});
    const result = try s.object();
    if (stage == .reload_callback) {
        const current_revision = try revision(s, try s.get(job, "agent"), self);
        _ = try s.invoke(self, "updateReadState", &.{ current_data, current_revision });
        try s.put(result, "result", current_data);
        return flow.settle(s.engine, job, false, result);
    }
    if (stage == .delete_result) {
        const key = try v.js.atom(s.engine, try s.get(parent, "provider"));
        defer c.JS_FreeAtom(s.engine.context, key);
        if (c.JS_DeleteProperty(s.engine.context, current_data, key, c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
        try s.set(parent, "latestData", current_data);
        try s.put(result, "result", c.pi_js_undefined());
        try s.put(result, "next", try stringify(s, current_data));
        return flow.settle(s.engine, job, false, result);
    }
    try s.put(job, "currentData", current_data);
    const current = try s.own(try v.js.getKey(s.engine, current_data, try s.get(parent, "provider")));
    return flow.wait(continued, s.engine, job, try s.call(try s.get(parent, "fn"), c.pi_js_undefined(), &.{current}), @intFromEnum(Stage.modify_callback));
}
fn modified(s: *Scope, job: c.JSValue, next: c.JSValue) !void {
    const parent = try s.get(job, "parent");
    const data = try s.get(job, "currentData");
    const result = try s.object();
    if (c.JS_IsUndefined(next)) {
        try s.set(parent, "latestData", data);
        try s.set(parent, "revision", try revision(s, try s.get(job, "agent"), try s.get(parent, "self")));
        try s.put(result, "result", try s.own(try v.js.getKey(s.engine, data, try s.get(parent, "provider"))));
    } else {
        const merged = try v.spread(s, data);
        const key = try v.js.atom(s.engine, try s.get(parent, "provider"));
        defer c.JS_FreeAtom(s.engine.context, key);
        if (c.JS_DefinePropertyValue(s.engine.context, merged, key, c.JS_DupValue(s.engine.context, next), c.JS_PROP_C_W_E) < 0) return v.js.capture(s.engine);
        try s.set(parent, "latestData", merged);
        try s.put(result, "result", next);
        try s.put(result, "next", try stringify(s, merged));
    }
    return flow.settle(s.engine, job, false, result);
}
fn fallback(s: *Scope, self: c.JSValue, job: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const reason = arg(args, 0);
            const tagged = c.pi_js_native_allocation_error_generation(reason);
            if (tagged != 0) {
                var low: u32 = 0;
                var high: u32 = 0;
                if (c.JS_ToUint32(engine.context, &low, try local.get(roots[1], "generationLow")) < 0 or c.JS_ToUint32(engine.context, &high, try local.get(roots[1], "generationHigh")) < 0) return v.js.capture(engine);
                const generation = (@as(u64, high) << 32) | low;
                const distance = tagged -% generation;
                if (distance != 0 and distance <= engine.native_allocation_generation -% generation) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            }
            return c.JS_DupValue(engine.context, try local.get(try local.get(roots[0], "readState"), "data"));
        }
    };
    return s.own(try funcs.createArrow(s.engine, "", 0, Adapter.call, &.{ self, job }));
}
fn latest(s: *Scope, job: c.JSValue) !void {
    const self = try s.get(job, "self");
    const options = try s.get(job, "options");
    try check(s, options);
    if (!s.truthy(try s.get(self, "authPath"))) {
        const reload_promise = try s.invoke(self, "reloadFromStorageAsync", &.{options});
        const result = if (s.truthy(try v.optional(s, options, "signal"))) reload_promise else try s.invoke(reload_promise, "catch", &.{try fallback(s, self, job)});
        return flow.wait(continued, s.engine, job, result, @intFromEnum(Stage.adopted));
    }
    const current_revision = try imported(s, try s.get(job, "agent"), "getFileRevision", &.{try s.get(self, "authPath")});
    if (!c.JS_IsUndefined(current_revision) and s.equal(current_revision, try s.get(try s.get(self, "readState"), "revision"))) return flow.settle(s.engine, job, false, try s.get(try s.get(self, "readState"), "data"));
    if (!s.truthy(try s.get(try s.get(self, "readState"), "reload"))) {
        const controller = try s.own(try v.js.builtin(s.engine, "AbortController", &.{}));
        const reload_state = try s.object();
        try s.put(reload_state, "controller", controller);
        const method = try s.get(self, "reloadFromStorageAsync");
        const reload_options = try s.object();
        try s.put(reload_options, "signal", try s.get(controller, "signal"));
        try s.put(reload_state, "promise", try s.call(method, self, &.{reload_options}));
        try s.put(reload_state, "readers", c.JS_NewInt32(s.engine.context, 0));
        try s.set(try s.get(self, "readState"), "reload", reload_state);
        _ = try s.invoke(try s.get(reload_state, "promise"), "then", &.{ try clearReload(s, self, reload_state), try clearReload(s, self, reload_state) });
    }
    const reload_state = try s.get(try s.get(self, "readState"), "reload");
    try s.put(job, "reload", reload_state);
    try changeReaders(s, reload_state, false);
    latestRace(s, job, reload_state) catch |err| {
        const reason = try s.own(flow.reason(s.engine, err));
        try releaseReader(s, self, reload_state);
        return flow.settle(s.engine, job, true, reason);
    };
}
fn clearReload(s: *Scope, self: c.JSValue, reload_state: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            if (local.equal(try local.get(try local.get(roots[0], "readState"), "reload"), roots[1])) try local.set(try local.get(roots[0], "readState"), "reload", c.pi_js_undefined());
            return c.pi_js_undefined();
        }
    };
    return s.own(try funcs.createArrow(s.engine, "", 0, Adapter.call, &.{ self, reload_state }));
}
fn changeReaders(s: *Scope, reload_state: c.JSValue, decrement: bool) !void {
    const numeric = try s.own(try s.engine.checked(c.JS_PiToNumeric(s.engine.context, try s.get(reload_state, "readers"))));
    const one = if (c.JS_IsBigInt(numeric)) try s.own(try s.engine.checked(c.JS_NewBigInt64(s.engine.context, 1))) else c.JS_NewInt32(s.engine.context, 1);
    try s.set(reload_state, "readers", try s.own(try arithmetic.binary(s.engine, if (decrement) .subtract else .add, numeric, one)));
}
fn releaseReader(s: *Scope, self: c.JSValue, reload_state: c.JSValue) !void {
    try changeReaders(s, reload_state, true);
    if (s.equal(try s.get(reload_state, "readers"), c.JS_NewInt32(s.engine.context, 0)) and s.equal(try s.get(try s.get(self, "readState"), "reload"), reload_state)) {
        try s.set(try s.get(self, "readState"), "reload", c.pi_js_undefined());
        _ = try s.invoke(try s.get(reload_state, "controller"), "abort", &.{});
    }
}
fn latestRace(s: *Scope, job: c.JSValue, reload_state: c.JSValue) !void {
    const options = try s.get(job, "options");
    const result = try s.own(try race(s.engine, try s.get(reload_state, "promise"), try v.optional(s, options, "signal")));
    const observed = if (s.truthy(try v.optional(s, options, "signal"))) result else try s.invoke(result, "catch", &.{try fallback(s, try s.get(job, "self"), job)});
    return flow.wait(continued, s.engine, job, observed, @intFromEnum(Stage.latest_result));
}
fn listMapper(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var iterator = try v.iterator(&s, arg(args, 0));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const provider = try s.own((try iterator.next()) orelse c.pi_js_undefined());
    const credential = try s.own((try iterator.next()) orelse c.pi_js_undefined());
    try iterator.close();
    const result = try s.object();
    try s.put(result, "providerId", provider);
    try s.put(result, "type", try s.get(credential, "type"));
    return c.JS_DupValue(engine.context, result);
}
fn continued(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .latest_result) {
        try releaseReader(&s, try s.get(job, "self"), try s.get(job, "reload"));
        return flow.settle(engine, job, rejected, value);
    }
    if (rejected) return flow.settle(engine, job, true, value);
    const self = try s.get(job, "self");
    switch (stage) {
        .adopted => return flow.settle(engine, job, false, value),
        .read => {
            const credential = try s.own(try v.js.getKey(engine, value, try s.get(job, "provider")));
            try check(&s, try s.get(job, "options"));
            if (!try v.eq(&s, try v.optional(&s, credential, "type"), "api_key") or c.JS_IsUndefined(try s.get(credential, "key"))) return flow.settle(engine, job, false, credential);
            const result = try v.spread(&s, credential);
            try s.put(result, "key", try imported(&s, try s.get(job, "agent"), "resolveConfigValue", &.{ try s.get(credential, "key"), try s.get(credential, "env") }));
            return flow.settle(engine, job, false, result);
        },
        .list => {
            const entries = try s.call(try s.get(job, "entries"), try s.get(job, "Object"), &.{value});
            try check(&s, try s.get(job, "options"));
            const mapper = try s.own(try funcs.createArrow(engine, "", 1, listMapper, &.{}));
            return flow.settle(engine, job, false, try s.invoke(entries, "map", &.{mapper}));
        },
        .modify_callback => return modified(&s, job, value),
        .modify_result => {
            _ = try s.invoke(self, "updateReadState", &.{ try s.get(job, "latestData"), try s.get(job, "revision") });
            return flow.settle(engine, job, false, value);
        },
        .delete_result => {
            _ = try s.invoke(self, "updateReadState", &.{try s.get(job, "latestData")});
            return flow.settle(engine, job, false, c.pi_js_undefined());
        },
        .memory_previous => {
            try check(&s, try s.get(job, "options"));
            return flow.wait(continued, engine, job, try s.call(try s.get(job, "fn"), c.pi_js_undefined(), &.{try s.get(self, "value")}), @intFromEnum(Stage.memory_callback));
        },
        .memory_callback => {
            const result = try s.get(value, "result");
            const next = try s.get(value, "next");
            try check(&s, try s.get(job, "options"));
            if (!c.JS_IsUndefined(next)) try s.set(self, "value", next);
            return flow.settle(engine, job, false, result);
        },
        else => unreachable,
    }
}
fn memoryConstructor(engine: *v.em.Engine, owner: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const prototype = try s.object();
    const Adapter = struct {
        fn constructMemory(host: *v.em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const self = try local.own(try class.object(host, target));
            try local.put(self, "value", c.pi_js_undefined());
            try local.put(self, "asyncChain", try local.invoke(try local.global("Promise"), "resolve", &.{}));
            return c.JS_DupValue(host.context, self);
        }
        fn sync(host: *v.em.Engine, self: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const response = try local.call(arg(args, 0), c.pi_js_undefined(), &.{try local.get(self, "value")});
            const result = try local.get(response, "result");
            const next = try local.get(response, "next");
            if (!c.JS_IsUndefined(next)) try local.set(self, "value", next);
            return c.JS_DupValue(host.context, result);
        }
        fn asyncLock(host: *v.em.Engine, self: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const previous = try local.get(self, "asyncChain");
            const pending = try flow.create(host, roots[0]);
            defer host.freeValue(pending.owner);
            defer host.freeValue(pending.promise);
            try local.put(pending.owner, "self", self);
            try local.put(pending.owner, "options", arg(args, 1));
            try local.put(pending.owner, "fn", arg(args, 0));
            startMemory(&local, pending.owner, previous) catch |err| try flow.rejectError(host, pending.owner, err);
            try local.set(self, "asyncChain", try local.invoke(pending.promise, "catch", &.{try noop(&local)}));
            return race(host, pending.promise, try v.optional(&local, arg(args, 1), "signal"));
        }
    };
    const result = try s.own(try class.constructor(engine, "InMemoryAuthStorageBackend", 0, prototype, Adapter.constructMemory, &.{}));
    try defineMethod(&s, prototype, "withLock", try methodValue(&s, "withLock", 1, Adapter.sync, &.{owner}, false));
    try defineMethod(&s, prototype, "withLockAsync", try methodValue(&s, "withLockAsync", 2, Adapter.asyncLock, &.{owner}, false));
    return c.JS_DupValue(engine.context, result);
}
fn startMemory(s: *Scope, job: c.JSValue, previous: c.JSValue) !void {
    return flow.wait(continued, s.engine, job, try s.invoke(previous, "catch", &.{try noop(s)}), @intFromEnum(Stage.memory_previous));
}
fn abortReason(s: *Scope, signal: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(try s.get(signal, "reason"))) return s.get(signal, "reason");
    const error_value = try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text("The operation was aborted")}));
    try s.set(error_value, "name", try s.text("AbortError"));
    return error_value;
}
fn race(engine: *v.em.Engine, operation: c.JSValue, signal: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (!s.truthy(signal)) return c.JS_DupValue(engine.context, operation);
    if (s.truthy(try s.get(signal, "aborted"))) {
        _ = try s.invoke(operation, "catch", &.{try noop(&s)});
        return c.JS_DupValue(engine.context, try s.invoke(try s.global("Promise"), "reject", &.{try abortReason(&s, signal)}));
    }
    const promise_constructor = try s.global("Promise");
    const owner = try s.object();
    try s.put(owner, "agent", signal);
    try s.put(owner, "operation", operation);
    const Adapter = struct {
        fn aborted(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            if (local.truthy(try local.get(roots[0], "settled"))) return c.pi_js_undefined();
            try local.set(roots[0], "settled", c.pi_js_bool(host.context, 1));
            const signal_value = try local.get(roots[0], "agent");
            _ = try local.invoke(signal_value, "removeEventListener", &.{ try local.text("abort"), try local.get(roots[0], "onAbort") });
            try flow.settle(host, roots[0], true, try abortReason(&local, signal_value));
            return c.pi_js_undefined();
        }
        fn fulfilled(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try raceDone(host, roots[0], arg(args, 0), false, 0);
            return c.pi_js_undefined();
        }
        fn rejected(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try raceDone(host, roots[0], arg(args, 0), true, 0);
            return c.pi_js_undefined();
        }
        fn executor(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const state = roots[0];
            try local.put(state, "resolve", arg(args, 0));
            try local.put(state, "reject", arg(args, 1));
            try local.put(state, "settled", c.pi_js_bool(host.context, 0));
            const signal_value = try local.get(state, "agent");
            const listener = try local.own(try funcs.createArrow(host, "onAbort", 0, @This().aborted, &.{state}));
            try local.put(state, "onAbort", listener);
            const options = try local.object();
            try local.put(options, "once", c.pi_js_bool(host.context, 1));
            _ = try local.invoke(signal_value, "addEventListener", &.{ try local.text("abort"), listener, options });
            _ = try local.invoke(try local.get(state, "operation"), "then", &.{ try local.own(try funcs.createArrow(host, "", 1, @This().fulfilled, &.{state})), try local.own(try funcs.createArrow(host, "", 1, @This().rejected, &.{state})) });
            if (local.truthy(try local.get(signal_value, "aborted"))) _ = try local.call(listener, c.pi_js_undefined(), &.{});
            return c.pi_js_undefined();
        }
    };
    const executor = try s.own(try funcs.createArrow(engine, "", 2, Adapter.executor, &.{owner}));
    return c.JS_DupValue(engine.context, try constructValue(&s, promise_constructor, &.{executor}));
}
fn raceDone(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (s.truthy(try s.get(owner, "settled"))) return;
    try s.set(owner, "settled", c.pi_js_bool(engine.context, 1));
    _ = try s.invoke(try s.get(owner, "agent"), "removeEventListener", &.{ try s.text("abort"), try s.get(owner, "onAbort") });
    return flow.settle(engine, owner, rejected, value);
}
