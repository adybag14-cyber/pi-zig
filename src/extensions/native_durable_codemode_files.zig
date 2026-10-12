//! Lazy, durable CodeMode output directory. Only successful environment results
//! become paths, and the directory is committed before any file is written.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const journal = @import("native_durable_codemode_journal.zig");
const c = em.c;
const Stage = enum(c_int) { read_directory, created_directory, recorded_directory, ready_directory, written };
fn wait(scope: *Scope, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    const root = try scope.get(state, "root");
    const docs = try scope.get(root, "documents");
    var captured: awaiting.Intrinsics = .{ .constructor = try scope.get(docs, "promiseConstructor"), .resolve = try scope.get(docs, "promiseResolve"), .then_function = try scope.get(docs, "promiseThen") };
    return scope.own(try awaiting.continueWith(advance, scope.engine, &captured, state, value, @intFromEnum(stage)));
}
fn errorValue(scope: *Scope, message: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "error", message);
    return value;
}
pub fn writer(engine: *em.Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root = try scope.object();
    inline for (.{ .{ "documents", docs }, .{ "api", api }, .{ "context", context } }) |field| try scope.put(root, field[0], field[1]);
    try scope.put(root, "env", try scope.get(api, "env"));
    var captures = [_]c.JSValue{root};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", 2, 0, captures.len, &captures));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return write(engine, captures[0], args[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn write(engine: *em.Engine, root: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const env = try scope.get(root, "env");
    if (c.JS_IsUndefined(env)) return c.JS_DupValue(engine.context, try errorValue(&scope, try scope.text("no execution environment")));
    const state = try scope.object();
    try scope.put(state, "root", root);
    try scope.put(state, "name", if (args.len > 0) args[0] else c.pi_js_undefined());
    try scope.put(state, "data", if (args.len > 1) args[1] else c.pi_js_undefined());
    var directory = try scope.get(root, "directory");
    if (c.JS_IsUndefined(directory)) {
        const pending = try scope.own(try journal.outputDirectory(engine, try scope.get(root, "documents"), try scope.get(root, "api"), try scope.get(root, "context"), null));
        directory = try wait(&scope, state, pending, .read_directory);
        try scope.put(root, "directory", directory);
    }
    return c.JS_DupValue(engine.context, try wait(&scope, state, directory, .ready_directory));
}
fn advance(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    const root = try scope.get(state, "root");
    const context = try scope.get(root, "context");
    const env = try scope.get(root, "env");
    if (rejected) {
        if (stage == .ready_directory or stage == .written) {
            const message = if (c.JS_IsObject(value)) try scope.get(value, "message") else try scope.stringify(value);
            return c.JS_DupValue(engine.context, try errorValue(&scope, message));
        }
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    }
    switch (stage) {
        .read_directory => {
            if (!c.JS_IsUndefined(value)) return c.JS_DupValue(engine.context, value);
            return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.invoke(env, "createTempDir", &.{ try scope.text("pi-codemode-"), context }), .created_directory));
        },
        .created_directory => {
            if (!scope.truthy(try scope.get(value, "ok"))) {
                const reason = try scope.own(try js.builtin(engine, "Error", &.{try scope.get(try scope.get(value, "error"), "message")}));
                return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            }
            return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.own(try journal.outputDirectory(engine, try scope.get(root, "documents"), try scope.get(root, "api"), context, try scope.get(value, "value"))), .recorded_directory));
        },
        .recorded_directory => return c.JS_DupValue(engine.context, value),
        .ready_directory => {
            const path = try scope.concat(try scope.concat(value, try scope.text("/")), try scope.get(state, "name"));
            try scope.put(state, "path", path);
            const pending = scope.invoke(env, "writeFile", &.{ path, try scope.get(state, "data"), context }) catch |err| {
                if (err != error.JavaScriptException or engine.captured_exception == null) return err;
                const reason = engine.captured_exception.?;
                const message = if (c.JS_IsObject(reason)) try scope.get(reason, "message") else try scope.stringify(reason);
                return c.JS_DupValue(engine.context, try errorValue(&scope, message));
            };
            return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .written));
        },
        .written => {
            const result = try scope.object();
            if (scope.truthy(try scope.get(value, "ok"))) try scope.put(result, "path", try scope.get(state, "path")) else try scope.put(result, "error", try scope.get(try scope.get(value, "error"), "message"));
            return c.JS_DupValue(engine.context, result);
        },
    }
}
