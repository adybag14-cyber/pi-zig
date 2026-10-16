//! Actual coding-agent models-store.ts classes at latest4954.
//! Each module instance owns the bounded shared path state. File I/O remains
//! the actual FileAuthStorageBackend import; no legacy store alias is used.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const flow = @import("native_sdk_async_actions.zig");
const functions = @import("native_node_function.zig");
const class = @import("native_class.zig");
const c = em.c;
pub const required_functions = .{ "join", "getAgentDir", "raceWithAbortSignal", "getFileRevision", "normalizePath", "stripBom", "FileAuthStorageBackend" };
const Method = enum(c_int) { parse, updateReadState, reloadFromStorage, readLatest, read, write, delete };
const Stage = enum(c_int) { storage, raced, read, mutation };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn construct(scope: *Scope, callable: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, callable, @intCast(args.len), @constCast(args.ptr))));
}
fn signal(scope: *Scope, options: c.JSValue) !c.JSValue {
    return if (temp.nullish(options)) c.pi_js_undefined() else scope.get(options, "signal");
}
fn check(scope: *Scope, options: c.JSValue) !void {
    const input = try signal(scope, options);
    if (!temp.nullish(input)) _ = try scope.invoke(input, "throwIfAborted", &.{});
}
fn clone(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.call(try scope.global("structuredClone"), c.pi_js_undefined(), &.{value});
}
pub fn create(engine: *em.Engine, actual_imports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (required_functions) |name| {
        const value = try scope.get(actual_imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualCodingAgentModelsStoreImport;
        try scope.put(bindings, name, value);
    }
    try scope.put(bindings, "sharedModelsFileReadState", c.pi_js_undefined());
    const output = try scope.object();
    inline for (.{ "InMemoryCodingAgentModelsStore", "FileModelsStore" }, 0..) |name, index| {
        const prototype = try scope.object();
        const constructor = try scope.own(try class.constructor(engine, name, 0, prototype, if (index == 0) memoryConstruct else fileConstruct, &.{bindings}));
        inline for (std.meta.fields(Method)) |field| {
            const method: Method = @enumFromInt(field.value);
            if (index == 0 and method != .read and method != .write and method != .delete) continue;
            const length: c_int = if (method == .write or method == .updateReadState) 3 else if (method == .parse) 1 else 2;
            const captures = [_]c.JSValue{ bindings, c.JS_NewInt32(engine.context, field.value) };
            const function = try scope.own(if (index == 0) try flow.native.create(engine, field.name, length, memoryAsync, &captures) else if (method != .parse and method != .updateReadState and method != .reloadFromStorage) try flow.native.createResumable(engine, field.name, length, fileBody, &captures) else try engine.checked(c.JS_NewCFunctionData2(engine.context, fileDispatch, field.name, length, field.value, captures.len, @constCast(&captures))));
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        }
        try scope.put(output, name, constructor);
    }
    return c.JS_DupValue(engine.context, output);
}
fn memoryConstruct(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const self = try scope.own(try class.object(engine, target));
    try scope.put(self, "entries", try construct(&scope, try scope.global("Map"), &.{}));
    return c.JS_DupValue(engine.context, self);
}
fn fileConstruct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const self = try scope.own(try class.object(engine, target));
    inline for (.{ "storage", "path", "readState" }) |name| try scope.put(self, name, c.pi_js_undefined());
    var path = arg(args, 0);
    if (c.JS_IsUndefined(path)) path = try imported(&scope, roots[0], "join", &.{ try imported(&scope, roots[0], "getAgentDir", &.{}), try scope.text("models-store.json") });
    try scope.set(self, "path", try imported(&scope, roots[0], "normalizePath", &.{path}));
    try scope.set(self, "storage", try construct(&scope, try scope.get(roots[0], "FileAuthStorageBackend"), &.{try scope.get(self, "path")}));
    const shared = try scope.get(roots[0], "sharedModelsFileReadState");
    const shared_path = if (temp.nullish(shared)) c.pi_js_undefined() else try scope.get(shared, "path");
    const state = if (scope.equal(shared_path, try scope.get(self, "path"))) try scope.get(shared, "readState") else blk: {
        const result = try scope.object();
        try scope.put(result, "data", try scope.object());
        break :blk result;
    };
    try scope.set(self, "readState", state);
    if (!scope.truthy(try scope.get(roots[0], "sharedModelsFileReadState"))) {
        const record = try scope.object();
        try scope.put(record, "path", try scope.get(self, "path"));
        try scope.put(record, "readState", try scope.get(self, "readState"));
        try scope.set(roots[0], "sharedModelsFileReadState", record);
    }
    return c.JS_DupValue(engine.context, self);
}
fn memoryAsync(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var method_id: i32 = undefined; if (c.JS_ToInt32(engine.context, &method_id, roots[1]) < 0) return js.capture(engine);
    const method: Method = @enumFromInt(method_id);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try check(&scope, arg(args, if (method == .write) 2 else 1));
    var result = c.pi_js_undefined();
    switch (method) {
        .read => {
            const entry = try scope.invoke(try scope.get(receiver, "entries"), "get", &.{arg(args, 0)});
            if (scope.truthy(entry)) result = try clone(&scope, entry);
        },
        .write => {
            // Member lookup precedes evaluation of the structuredClone argument.
            const entries = try scope.get(receiver, "entries");
            const set = try scope.get(entries, "set");
            _ = try scope.call(set, entries, &.{ arg(args, 0), try clone(&scope, arg(args, 1)) });
        },
        .delete => _ = try scope.invoke(try scope.get(receiver, "entries"), "delete", &.{arg(args, 0)}),
        else => unreachable,
    }
    return c.JS_DupValue(engine.context, result);
}
fn fileDispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(magic);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return fileSync(engine, receiver, roots[0], method, args) catch |err| sdk.fail(engine, err);
}
fn fileSync(engine: *em.Engine, receiver: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .parse => return c.JS_DupValue(engine.context, if (scope.truthy(arg(args, 0))) try scope.invoke(try scope.global("JSON"), "parse", &.{try imported(&scope, bindings, "stripBom", &.{arg(args, 0)})}) else try scope.object()),
        .updateReadState => {
            try scope.set(arg(args, 0), "data", arg(args, 1));
            try scope.set(arg(args, 0), "revision", arg(args, 2));
            return c.pi_js_undefined();
        },
        .reloadFromStorage => {
            const storage = try scope.get(receiver, "storage");
            const with_lock = try scope.get(storage, "withLockAsync");
            const callback = try scope.own(try flow.native.createArrow(engine, "", 1, reloadCallback, &.{ receiver, bindings, arg(args, 0) }, receiver));
            return c.JS_DupValue(engine.context, try scope.call(with_lock, storage, &.{ callback, arg(args, 1) }));
        },
        else => unreachable,
    }
}
fn reloadCallback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return reloadBody(engine, arg(args, 0), roots);
}
fn reloadBody(engine: *em.Engine, content: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const data = try scope.invoke(roots[0], "parse", &.{content});
    const update = try scope.get(roots[0], "updateReadState");
    _ = try scope.call(update, roots[0], &.{ roots[2], data, try imported(&scope, roots[1], "getFileRevision", &.{try scope.get(roots[0], "path")}) });
    const result = try scope.object();
    try scope.put(result, "result", data);
    return c.JS_DupValue(engine.context, result);
}
fn fileBody(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: flow.native.Completion, input: c.JSValue) !flow.native.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (completion == .rejected and try flow.nativeAllocationReason(engine, state.*, input)) {
        if (try flow.body.stage(&scope, state.*) == @intFromEnum(Stage.raced)) finishReader(&scope, state.*) catch {};
        return error.OutOfMemory;
    }
    if (completion == .start) {
        const owner = try flow.init(&scope, state);
        var method_id: i32 = undefined; if (c.JS_ToInt32(engine.context, &method_id, roots[1]) < 0) return js.capture(engine);
        fileStart(engine, owner, receiver, roots[0], @enumFromInt(method_id), args) catch |err| try flow.rejectError(engine, owner, err);
    } else continueFile(engine, state.*, input, completion == .rejected, try flow.body.stage(&scope, state.*)) catch |err| try flow.rejectError(engine, state.*, err);
    return flow.body.action(&scope, state.*);
}
fn fileStart(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "self", receiver);
    try scope.put(owner, "bindings", bindings);
    try scope.put(owner, "options", arg(args, if (method == .write) 2 else 1));
    try scope.put(owner, "id", arg(args, 0));
    if (method == .readLatest) return startLatest(engine, owner, arg(args, 0));
    if (method == .read) return flow.wait(continueFile, engine, owner, try scope.invoke(receiver, "readLatest", &.{ try scope.get(receiver, "readState"), try scope.get(owner, "options") }), @intFromEnum(Stage.read));
    try scope.put(owner, "entry", arg(args, 1));
    try scope.put(owner, "latest", c.pi_js_undefined());
    try scope.put(owner, "delete", c.pi_js_bool(engine.context, @intFromBool(method == .delete)));
    const storage = try scope.get(receiver, "storage");
    const with_lock = try scope.get(storage, "withLockAsync");
    const callback = try scope.own(try flow.native.createArrow(engine, "", 1, mutationCallback, &.{owner}, receiver));
    return flow.wait(continueFile, engine, owner, try scope.call(with_lock, storage, &.{ callback, try scope.get(owner, "options") }), @intFromEnum(Stage.mutation));
}
fn startLatest(engine: *em.Engine, owner: c.JSValue, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = try scope.get(owner, "options");
    try check(&scope, options);
    const self = try scope.get(owner, "self");
    const revision = try imported(&scope, try scope.get(owner, "bindings"), "getFileRevision", &.{try scope.get(self, "path")});
    if (!c.JS_IsUndefined(revision) and scope.equal(revision, try scope.get(state, "revision"))) return flow.settle(engine, owner, false, try scope.get(state, "data"));
    if (!scope.truthy(try scope.get(state, "reload"))) {
        const controller = try construct(&scope, try scope.global("AbortController"), &.{});
        const reload = try scope.object();
        try scope.put(reload, "controller", controller);
        const reload_options = try scope.object();
        try scope.put(reload_options, "signal", try scope.get(controller, "signal"));
        try scope.put(reload, "promise", try scope.invoke(self, "reloadFromStorage", &.{ state, reload_options }));
        try scope.put(reload, "readers", c.JS_NewInt32(engine.context, 0));
        try scope.set(state, "reload", reload);
        const promise = try scope.get(reload, "promise");
        const then = try scope.get(promise, "then");
        const on_done = try scope.own(try functions.createArrow(engine, "", 0, clearReload, &.{ state, reload }));
        const on_error = try scope.own(try functions.createArrow(engine, "", 0, clearReload, &.{ state, reload }));
        _ = try scope.call(then, promise, &.{ on_done, on_error });
    }
    const reload = try scope.get(state, "reload");
    try scope.put(owner, "state", state);
    try scope.put(owner, "reload", reload);
    const readers = try scope.get(reload, "readers");
    try scope.set(reload, "readers", try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, readers))));
    waitRace(engine, owner) catch |err| {
        // The original failure reason must survive successful finally cleanup.
        const reason = try scope.own(flow.reason(engine, err));
        try finishReader(&scope, owner);
        return flow.settle(engine, owner, true, reason);
    };
}
fn waitRace(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try imported(&scope, try scope.get(owner, "bindings"), "raceWithAbortSignal", &.{ try scope.get(try scope.get(owner, "reload"), "promise"), try signal(&scope, try scope.get(owner, "options")) });
    try flow.wait(continueFile, engine, owner, pending, @intFromEnum(Stage.raced));
}
fn clearReload(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.equal(try scope.get(roots[0], "reload"), roots[1])) try scope.set(roots[0], "reload", c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn finishReader(scope: *Scope, owner: c.JSValue) !void {
    const reload = try scope.get(owner, "reload");
    try scope.set(reload, "readers", try scope.own(try scope.engine.checked(c.JS_PiDecrement(scope.engine.context, try scope.get(reload, "readers")))));
    if (scope.equal(try scope.get(reload, "readers"), c.JS_NewInt32(scope.engine.context, 0)) and scope.equal(try scope.get(try scope.get(owner, "state"), "reload"), reload)) {
        try scope.set(try scope.get(owner, "state"), "reload", c.pi_js_undefined());
        _ = try scope.invoke(try scope.get(reload, "controller"), "abort", &.{});
    }
}
fn mutationCallback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return mutationBody(engine, roots[0], arg(args, 0));
}
fn mutationBody(engine: *em.Engine, owner: c.JSValue, content: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const current = try scope.invoke(try scope.get(owner, "self"), "parse", &.{content});
    const id = try scope.get(owner, "id");
    // ToPropertyKey is evaluated before the write's structuredClone RHS.
    const property_key = try scope.own(try engine.checked(c.JS_ToPropertyKey(engine.context, id)));
    if (scope.truthy(try scope.get(owner, "delete"))) {
        const atom = try js.atom(engine, property_key);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DeleteProperty(engine.context, current, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
    } else try js.setKey(engine, current, property_key, try clone(&scope, try scope.get(owner, "entry")));
    try scope.set(owner, "latest", current);
    const result = try scope.object();
    try scope.put(result, "result", c.pi_js_undefined());
    try scope.put(result, "next", try scope.invoke(try scope.global("JSON"), "stringify", &.{ current, c.pi_js_null(), c.JS_NewInt32(engine.context, 2) }));
    return c.JS_DupValue(engine.context, result);
}
fn continueFile(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    finishFile(engine, owner, value, rejected, @enumFromInt(raw)) catch |err| try flow.rejectError(engine, owner, err);
}
fn finishFile(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == .raced) {
        try finishReader(&scope, owner);
        return flow.settle(engine, owner, rejected, value);
    }
    if (rejected) return flow.settle(engine, owner, true, value);
    if (stage == .read) {
        const entry = try scope.own(try js.getKey(engine, value, try scope.get(owner, "id")));
        try check(&scope, try scope.get(owner, "options"));
        return flow.settle(engine, owner, false, if (scope.truthy(entry)) try clone(&scope, entry) else c.pi_js_undefined());
    }
    const latest = try scope.get(owner, "latest");
    if (scope.truthy(latest)) {
        const self = try scope.get(owner, "self");
        _ = try scope.invoke(self, "updateReadState", &.{ try scope.get(self, "readState"), latest });
    }
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
