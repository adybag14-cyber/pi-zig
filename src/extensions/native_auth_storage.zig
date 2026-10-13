//! Native AuthStorage orchestration over app-owned storage and real file locks.
//! Credentials remain raw JavaScript values, preserving provider env/extra data.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const fileio = @import("native_auth_file_io.zig");
const backend = @import("native_auth_file_backend.zig");
const c = em.c;
const Method = enum(c_int) { reload, read, list, modify, delete };
const Stage = enum(c_int) { read_ready, modified, deleted };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn parse(scope: *Scope, raw: c.JSValue) !c.JSValue {
    if (!scope.truthy(raw)) return scope.object();
    var text = raw;
    const first = try scope.invoke(text, "charCodeAt", &.{c.JS_NewInt32(scope.engine.context, 0)});
    var code: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &code, first) < 0) return js.capture(scope.engine);
    if (code == 0xfeff) text = try scope.invoke(text, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)});
    return scope.invoke(try scope.global("JSON"), "parse", &.{text});
}
fn serialized(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("JSON"), "stringify", &.{ value, c.pi_js_null(), c.JS_NewInt32(scope.engine.context, 2) });
}
fn check(scope: *Scope, options: c.JSValue) !void {
    if (nullish(options)) return;
    const signal = try scope.get(options, "signal");
    if (!nullish(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
}
fn revision(scope: *Scope, state: c.JSValue) !c.JSValue {
    const path = try scope.get(state, "path");
    if (c.JS_IsUndefined(path)) return c.pi_js_undefined();
    const text = try scope.engine.toString(path);
    defer scope.engine.gpa.free(text);
    const raw = try fileio.revision(scope.engine, text) orelse return c.pi_js_undefined();
    defer scope.engine.gpa.free(raw);
    return scope.text(raw);
}
fn readState(scope: *Scope, state: c.JSValue) !c.JSValue {
    return scope.get(state, "readState");
}
fn update(scope: *Scope, state: c.JSValue, data: c.JSValue, rev: c.JSValue) !void {
    const target = try readState(scope, state);
    try scope.put(target, "data", data);
    try scope.put(target, "revision", rev);
}
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const cache = try scope.object();
    var intrinsics = try awaiting.Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    try scope.put(cache, "promise_constructor", intrinsics.constructor);
    try scope.put(cache, "promise_resolve", intrinsics.resolve);
    try scope.put(cache, "promise_then", intrinsics.then_function);
    try backend.install(engine, exports, cache);
    var captures = [_]c.JSValue{cache};
    const constructor = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, createCallback, "AuthStorage", 1, 1, captures.len, &captures)));
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    inline for (.{ "create", "fromStorage" }, 0..) |name, index| try scope.put(constructor, name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, createCallback, name, 1, @intCast(index), captures.len, &captures))));
    try scope.put(exports, "AuthStorage", constructor);
    try @import("native_auth_readonly.zig").install(engine, exports);
}
fn createCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined(), magic == 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn create(engine: *em.Engine, cache: c.JSValue, input: c.JSValue, file: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "cache", cache);
    try scope.put(state, "path", if (file) input else c.pi_js_undefined());
    try scope.put(state, "backend", if (file) try scope.own(try backend.create(engine, cache, input)) else input);
    var shared = try scope.get(cache, "sharedReadState");
    const shared_path = try scope.get(cache, "sharedPath");
    if (!file or c.JS_IsUndefined(shared) or !scope.equal(shared_path, input)) {
        shared = try scope.object();
        try scope.put(shared, "data", try scope.object());
        try scope.put(shared, "revision", c.pi_js_undefined());
        if (file and c.JS_IsUndefined(shared_path)) {
            try scope.put(cache, "sharedPath", input);
            try scope.put(cache, "sharedReadState", shared);
        }
    }
    try scope.put(state, "readState", shared);
    const current_revision = try revision(&scope, state);
    if (c.JS_IsUndefined(current_revision) or !scope.equal(current_revision, try scope.get(shared, "revision"))) try bestEffortReload(&scope, state);
    const result = try scope.object();
    var data = [_]c.JSValue{state};
    inline for (std.meta.fields(Method)) |field| try scope.put(result, field.name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, switch (@as(Method, @enumFromInt(field.value))) {
        .reload, .list => 0,
        .modify => 2,
        else => 1,
    }, field.value, data.len, &data))));
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(raw);
    return invoke(engine, data[0], method, args[0..@intCast(argc)]) catch |err| if (method == .reload) @import("native_durable.zig").reject(engine, err) else @import("native_durable.zig").rejectedPromise(engine, err);
}
fn callbackFunction(scope: *Scope, job: c.JSValue, magic: c_int) !c.JSValue {
    var data = [_]c.JSValue{job};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, storageCallback, "", 1, magic, data.len, &data)));
}
fn reload(scope: *Scope, state: c.JSValue) !void {
    const job = try scope.object();
    try scope.put(job, "state", state);
    _ = try scope.invoke(try scope.get(state, "backend"), "withLock", &.{try callbackFunction(scope, job, 0)});
}
fn bestEffortReload(scope: *Scope, state: c.JSValue) !void {
    // Source deliberately ignores storage/parse errors while retaining its
    // last snapshot. A native allocator failure is an owner control failure,
    // not an unavailable credential file. Preserve only that private signal.
    const generation = scope.engine.native_allocation_generation;
    reload(scope, state) catch |err| {
        if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    };
}
fn intrinsic(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    const cache = try scope.get(state, "cache");
    return .{ .constructor = try scope.get(cache, "promise_constructor"), .resolve = try scope.get(cache, "promise_resolve"), .then_function = try scope.get(cache, "promise_then") };
}
fn wait(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsic(scope, try scope.get(job, "state"));
    return scope.own(try awaiting.continueWith(advance, scope.engine, &captured, job, value, @intFromEnum(stage)));
}
fn invoke(engine: *em.Engine, state: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .reload) {
        try bestEffortReload(&scope, state);
        return c.pi_js_undefined();
    }
    const options_index: usize = if (method == .modify) 2 else if (method == .list) 0 else 1;
    const options = if (args.len > options_index) args[options_index] else c.pi_js_undefined();
    try check(&scope, options);
    const job = try scope.object();
    try scope.put(job, "state", state);
    try scope.put(job, "options", options);
    // Two exact u32 words avoid a guest-number rounding boundary at 2^53.
    const generation = engine.native_allocation_generation;
    try scope.put(job, "nativeGenerationLow", c.JS_NewInt64(engine.context, @as(u32, @truncate(generation))));
    try scope.put(job, "nativeGenerationHigh", c.JS_NewInt64(engine.context, @as(u32, @truncate(generation >> 32))));
    try scope.put(job, "id", if (args.len > 0) args[0] else c.pi_js_undefined());
    try scope.put(job, "list", c.pi_js_bool(engine.context, @intFromBool(method == .list)));
    if (method == .read or method == .list) {
        const rev = try revision(&scope, state);
        const stored = try readState(&scope, state);
        if (!c.JS_IsUndefined(rev) and scope.equal(rev, try scope.get(stored, "revision"))) return c.JS_DupValue(engine.context, try wait(&scope, job, try scope.get(stored, "data"), .read_ready));
        const pending = try scope.invoke(try scope.get(state, "backend"), "withLockAsync", &.{ try callbackFunction(&scope, job, 3), options });
        return c.JS_DupValue(engine.context, try wait(&scope, job, pending, .read_ready));
    }
    try scope.put(job, "latest", try scope.get(try readState(&scope, state), "data"));
    try scope.put(job, "revision", c.pi_js_undefined());
    if (method == .modify) try scope.put(job, "fn", if (args.len > 1) args[1] else c.pi_js_undefined());
    const pending = try scope.invoke(try scope.get(state, "backend"), "withLockAsync", &.{ try callbackFunction(&scope, job, if (method == .modify) 1 else 2), options });
    return c.JS_DupValue(engine.context, try wait(&scope, job, pending, if (method == .modify) .modified else .deleted));
}
fn storageCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return storageCall(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined(), magic) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn storageCall(engine: *em.Engine, job: c.JSValue, text: c.JSValue, magic: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.get(job, "state");
    const data = try parse(&scope, text);
    const result = try scope.object();
    if (magic == 0 or magic == 3) {
        try update(&scope, state, data, try revision(&scope, state));
        try scope.put(result, "result", if (magic == 0) c.pi_js_undefined() else data);
        return c.JS_DupValue(engine.context, result);
    }
    const id = try scope.get(job, "id");
    if (magic == 2) {
        const atom = try js.atom(engine, id);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DeleteProperty(engine.context, data, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
        try scope.put(job, "latest", data);
        try scope.put(result, "result", c.pi_js_undefined());
        try scope.put(result, "next", try serialized(&scope, data));
        return c.JS_DupValue(engine.context, result);
    }
    try scope.put(job, "currentData", data);
    try scope.put(job, "current", try scope.own(try js.getKey(engine, data, id)));
    const pending = try scope.call(try scope.get(job, "fn"), c.pi_js_undefined(), &.{try scope.get(job, "current")});
    var captured = try intrinsic(&scope, state);
    return awaiting.continueWith(modified, engine, &captured, job, pending, 0);
}
fn modified(engine: *em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.get(job, "state");
    const data = try scope.get(job, "currentData");
    const result = try scope.object();
    if (c.JS_IsUndefined(value)) {
        try scope.put(job, "latest", data);
        try scope.put(job, "revision", try revision(&scope, state));
        try scope.put(result, "result", try scope.get(job, "current"));
        return c.JS_DupValue(engine.context, result);
    }
    const merged = try scope.own(try js.spread(engine, data));
    const id = try scope.get(job, "id");
    const atom = try js.atom(engine, id);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, merged, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    try scope.put(job, "latest", merged);
    try scope.put(result, "result", value);
    try scope.put(result, "next", try serialized(&scope, merged));
    return c.JS_DupValue(engine.context, result);
}
pub fn resolvedCredential(scope: *Scope, credential: c.JSValue) !c.JSValue {
    if (nullish(credential) or !scope.equal(try scope.get(credential, "type"), try scope.text("api_key")) or c.JS_IsUndefined(try scope.get(credential, "key"))) return credential;
    const key = try scope.get(credential, "key");
    const text = try scope.engine.toString(key);
    defer scope.engine.gpa.free(text);
    // Command-backed resolution is wired through the process-owned adapter;
    // this initial bridge resolves literal/environment templates directly.
    const result = try scope.own(try js.spread(scope.engine, credential));
    if (@import("../coding_agent/config_value.zig").isCommandConfigValue(text)) return result;
    var environment: std.process.Environ.Map = .init(scope.engine.gpa);
    defer environment.deinit();
    const references = try @import("native_sdk_config_value.zig").names(scope.engine.gpa, text);
    defer scope.engine.gpa.free(references);
    const supplied = try scope.get(credential, "env");
    for (references) |name| {
        const property = try scope.text(name);
        var value = if (nullish(supplied)) c.pi_js_undefined() else try scope.own(try js.getKey(scope.engine, supplied, property));
        if (!scope.truthy(value)) {
            const process = try scope.global("process");
            if (!nullish(process)) value = try scope.own(try js.getKey(scope.engine, try scope.get(process, "env"), property));
        }
        if (scope.truthy(value)) {
            const content = try scope.engine.toString(value);
            defer scope.engine.gpa.free(content);
            try environment.put(name, content);
        }
    }
    const resolved = try @import("../coding_agent/config_value.zig").resolveTemplate(scope.engine.gpa, &environment, text);
    defer if (resolved) |value| scope.engine.gpa.free(value);
    try scope.put(result, "key", if (resolved) |value| try scope.text(value) else c.pi_js_undefined());
    return result;
}
fn nativeAllocationReason(scope: *Scope, job: c.JSValue, value: c.JSValue) !bool {
    const tagged = c.pi_js_native_allocation_error_generation(value);
    if (tagged == 0) return false;
    var low: u32 = 0;
    var high: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &low, try scope.get(job, "nativeGenerationLow")) < 0 or c.JS_ToUint32(scope.engine.context, &high, try scope.get(job, "nativeGenerationHigh")) < 0) return js.capture(scope.engine);
    const generation = (@as(u64, high) << 32) | low;
    const distance = tagged -% generation;
    return distance != 0 and distance <= scope.engine.native_allocation_generation -% generation;
}
fn advance(engine: *em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    const state = try scope.get(job, "state");
    const options = try scope.get(job, "options");
    if (stage == .read_ready) {
        var data = value;
        if (rejected) {
            // The marker is private native object identity, not a guest error
            // name/message. Ordinary Source failures still use cached data.
            if (try nativeAllocationReason(&scope, job, value)) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
            const signal = if (nullish(options)) c.pi_js_undefined() else try scope.get(options, "signal");
            if (!nullish(signal)) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
            data = try scope.get(try readState(&scope, state), "data");
        }
        try check(&scope, options);
        if (scope.truthy(try scope.get(job, "list"))) {
            const entries = try scope.invoke(try scope.global("Object"), "entries", &.{data});
            const list = try scope.array();
            for (0..try @import("native_values.zig").length(engine, entries)) |i| {
                const pair = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(i))));
                const id = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 0)));
                const credential = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 1)));
                const item = try scope.object();
                try scope.put(item, "providerId", id);
                try scope.put(item, "type", try scope.get(credential, "type"));
                try scope.index(list, @intCast(i), item);
            }
            return c.JS_DupValue(engine.context, list);
        }
        return c.JS_DupValue(engine.context, try resolvedCredential(&scope, try scope.own(try js.getKey(engine, data, try scope.get(job, "id")))));
    }
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    try update(&scope, state, try scope.get(job, "latest"), try scope.get(job, "revision"));
    return c.JS_DupValue(engine.context, if (stage == .deleted) c.pi_js_undefined() else value);
}
