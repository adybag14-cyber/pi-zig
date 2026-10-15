//! Actual auth/helpers.ts and auth/context.ts bodies over owner-thread VM values.
//! Async boundaries retain callback/credential identity and native GC roots.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const Stage = enum(c_int) { login, env, lazy, delegated, file_module, file_os, file_access };

pub fn asyncArrow(engine: *v.em.Engine, name: [*:0]const u8, length: c_int, callback: functions.Callback, roots: []const c.JSValue) !c.JSValue {
    const value = try functions.createArrow(engine, name, length, callback, roots);
    errdefer engine.freeValue(value);
    const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, value, prototype) < 0) return v.js.capture(engine);
    return value;
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    try scope.put(exports, "envApiKeyAuth", try scope.own(try functions.create(engine, "envApiKeyAuth", 2, envFactory, &.{})));
    try scope.put(exports, "lazyOAuth", try scope.own(try functions.create(engine, "lazyOAuth", 1, lazyFactory, &.{})));
    return c.JS_DupValue(engine.context, exports);
}
pub fn envApiKeyAuth(engine: *v.em.Engine, name: c.JSValue, env_vars: c.JSValue) !c.JSValue {
    return envFactory(engine, c.pi_js_undefined(), &.{ name, env_vars }, &.{});
}
pub fn lazyOAuth(engine: *v.em.Engine, input: c.JSValue) !c.JSValue {
    return lazyFactory(engine, c.pi_js_undefined(), &.{input}, &.{});
}
pub fn defaultProviderAuthContext(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "env", try scope.own(try asyncArrow(engine, "env", 1, contextEnv, &.{})));
    try scope.put(result, "fileExists", try scope.own(try asyncArrow(engine, "fileExists", 1, fileExists, &.{})));
    return c.JS_DupValue(engine.context, result);
}
fn contextEnv(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    readContextEnv(&scope, pending.owner, argument(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn readContextEnv(scope: *Scope, owner: c.JSValue, name: c.JSValue) !void {
    const process = try scope.global("process");
    const env = try v.optional(scope, process, "env");
    const value = if (v.nullish(env)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, env, name));
    const valid = c.JS_IsString(value) and try v.length(scope, try scope.invoke(value, "trim", &.{})) > 0;
    return flow.settle(scope.engine, owner, false, if (valid) value else c.pi_js_undefined());
}
fn fileExists(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const generation = engine.native_allocation_generation;
    startFileExists(&scope, pending.owner, argument(args, 0)) catch |err| {
        try @import("native_ai_partial_json.zig").discard(engine, err, generation);
        try flow.settle(engine, pending.owner, false, c.pi_js_bool(engine.context, 0));
    };
    return pending.promise;
}
fn startFileExists(scope: *Scope, owner: c.JSValue, path: c.JSValue) !void {
    try scope.put(owner, "path", path);
    // Source imports the builtin module; global require is not involved.
    const module = scope.engine.native_module_values.get("node:fs/promises") orelse return error.NativeAuthFilesystemUnavailable;
    return flow.wait(continued, scope.engine, owner, module, @intFromEnum(Stage.file_module));
}
fn osModule(scope: *Scope) !c.JSValue {
    if (scope.engine.native_module_values.get("node:os")) |module| return module;
    // A private homedir binding implements only this imported dependency. It
    // does not register or advertise an incomplete public node:os namespace.
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return @import("native_home.zig").get(engine);
        }
    };
    const module = try scope.object();
    try scope.put(module, "homedir", try scope.own(try functions.create(scope.engine, "homedir", 0, Adapter.call, &.{})));
    return module;
}
fn accessFile(scope: *Scope, owner: c.JSValue, path: c.JSValue) !void {
    return flow.wait(continued, scope.engine, owner, try scope.invoke(try scope.get(owner, "fs"), "access", &.{path}), @intFromEnum(Stage.file_access));
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn envFactory(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = argument(args, 0);
    const env_vars = argument(args, 1);
    const result = try scope.object();
    try scope.put(result, "name", name);
    try scope.put(result, "login", try scope.own(try asyncArrow(engine, "login", 1, login, &.{name})));
    try scope.put(result, "resolve", try scope.own(try asyncArrow(engine, "resolve", 1, resolve, &.{env_vars})));
    return c.JS_DupValue(engine.context, result);
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startLogin(&scope, pending.owner, argument(args, 0), roots[0]) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startLogin(scope: *Scope, owner: c.JSValue, interaction: c.JSValue, name: c.JSValue) !void {
    try scope.put(owner, "interaction", interaction);
    _ = try scope.invoke(try scope.get(interaction, "signal"), "throwIfAborted", &.{});
    const prompt_method = try scope.get(interaction, "prompt");
    const prompt = try scope.object();
    try scope.put(prompt, "type", try scope.text("secret"));
    try scope.put(prompt, "message", try scope.concat(try scope.text("Enter "), try scope.stringify(name)));
    try flow.wait(continued, scope.engine, owner, try scope.call(prompt_method, interaction, &.{prompt}), @intFromEnum(Stage.login));
}
fn resolve(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startResolve(&scope, pending.owner, argument(args, 0), roots[0]) catch |err| try rejectResolve(&scope, pending.owner, err);
    return pending.promise;
}
fn stored(scope: *Scope, credential: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const auth = try scope.object();
    try scope.put(auth, "apiKey", try scope.get(credential, "key"));
    try scope.put(result, "auth", auth);
    try scope.put(result, "env", try scope.get(credential, "env"));
    try scope.put(result, "source", try scope.text("stored credential"));
    return result;
}
fn startResolve(scope: *Scope, owner: c.JSValue, input: c.JSValue, env_vars: c.JSValue) !void {
    // Preserve parameter destructuring before entering the async body.
    const ctx = try scope.get(input, "ctx");
    const credential = try scope.get(input, "credential");
    const signal = try scope.get(input, "signal");
    try scope.put(owner, "ctx", ctx);
    try scope.put(owner, "signal", signal);
    _ = try scope.invoke(signal, "throwIfAborted", &.{});
    if (scope.truthy(try v.optional(scope, credential, "key"))) return flow.settle(scope.engine, owner, false, try stored(scope, credential));
    var iterator = try v.iterator(scope, env_vars);
    defer iterator.deinit();
    try scope.put(owner, "iterator", iterator.iterator);
    try scope.put(owner, "next", iterator.next_function);
    try scope.put(owner, "closed", c.pi_js_bool(scope.engine.context, 0));
    return nextEnv(scope, owner);
}
fn iteratorFor(scope: *Scope, owner: c.JSValue) !v.js.Iterator {
    return .{ .engine = scope.engine, .iterator = c.JS_DupValue(scope.engine.context, try scope.get(owner, "iterator")), .next_function = c.JS_DupValue(scope.engine.context, try scope.get(owner, "next")), .closed = scope.truthy(try scope.get(owner, "closed")) };
}
fn nextEnv(scope: *Scope, owner: c.JSValue) !void {
    var iterator = try iteratorFor(scope, owner);
    defer iterator.deinit();
    const entry = iterator.next() catch |err| {
        try scope.put(owner, "closed", c.pi_js_bool(scope.engine.context, 1));
        return err;
    };
    try scope.put(owner, "closed", c.pi_js_bool(scope.engine.context, @intFromBool(iterator.closed)));
    const name = try scope.own(entry orelse return flow.settle(scope.engine, owner, false, c.pi_js_undefined()));
    try scope.put(owner, "envName", name);
    return flow.wait(continued, scope.engine, owner, try scope.invoke(try scope.get(owner, "ctx"), "env", &.{name}), @intFromEnum(Stage.env));
}
fn closeIterator(scope: *Scope, owner: c.JSValue) !void {
    if (v.nullish(try scope.get(owner, "iterator"))) return;
    var iterator = try iteratorFor(scope, owner);
    defer iterator.deinit();
    try scope.put(owner, "closed", c.pi_js_bool(scope.engine.context, 1));
    return iterator.close();
}
fn rejectResolve(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = try scope.own(flow.reason(scope.engine, err));
    return rejectReason(scope, owner, reason);
}
fn rejectReason(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const generation = scope.engine.native_allocation_generation;
    closeIterator(scope, owner) catch |err| try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
    return flow.settle(scope.engine, owner, true, reason);
}
fn lazyFactory(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = argument(args, 0);
    const state = try scope.object();
    try scope.put(state, "input", input);
    try scope.put(state, "promise", c.pi_js_undefined());
    const result = try scope.object();
    inline for (.{ "name", "isSubscription", "loginLabel" }) |name| try scope.put(result, name, try scope.get(input, name));
    inline for (.{ "login", "refresh", "toAuth" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, call_args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                const pending = try flow.create(host, roots[0]);
                defer host.freeValue(pending.owner);
                errdefer host.freeValue(pending.promise);
                startLazy(&local, pending.owner, call_args, name, index == 2) catch |err| try flow.rejectError(host, pending.owner, err);
                return pending.promise;
            }
        };
        try scope.put(result, name, try scope.own(try asyncArrow(engine, name, if (index == 2) 1 else 2, Adapter.call, &.{state})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn startLazy(scope: *Scope, owner: c.JSValue, args: []const c.JSValue, name: []const u8, one: bool) !void {
    const arguments = try scope.array();
    try scope.index(arguments, 0, argument(args, 0));
    if (!one) try scope.index(arguments, 1, argument(args, 1));
    try scope.put(owner, "arguments", arguments);
    try scope.put(owner, "method", try scope.text(name));
    const state = try scope.get(owner, "agent");
    var loaded = try scope.get(state, "promise");
    if (v.nullish(loaded)) {
        loaded = try scope.invoke(try scope.get(state, "input"), "load", &.{});
        try scope.put(state, "promise", loaded);
    }
    return flow.wait(continued, scope.engine, owner, loaded, @intFromEnum(Stage.lazy));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .env) return rejectReason(&scope, owner, value);
        if (stage == .file_module or stage == .file_os or stage == .file_access) return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
        return flow.settle(engine, owner, true, value);
    }
    const generation = engine.native_allocation_generation;
    advance(&scope, owner, value, stage) catch |err| {
        if (stage == .env) return rejectResolve(&scope, owner, err);
        if (stage == .file_module or stage == .file_os or stage == .file_access) {
            try @import("native_ai_partial_json.zig").discard(engine, err, generation);
            return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
        }
        return flow.rejectError(engine, owner, err);
    };
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .login => {
            _ = try scope.invoke(try scope.get(try scope.get(owner, "interaction"), "signal"), "throwIfAborted", &.{});
            const credential = try scope.object();
            try scope.put(credential, "type", try scope.text("api_key"));
            try scope.put(credential, "key", value);
            return flow.settle(scope.engine, owner, false, credential);
        },
        .env => {
            _ = try scope.invoke(try scope.get(owner, "signal"), "throwIfAborted", &.{});
            if (!scope.truthy(value)) return nextEnv(scope, owner);
            const result = try scope.object();
            const auth = try scope.object();
            try scope.put(auth, "apiKey", value);
            try scope.put(result, "auth", auth);
            try scope.put(result, "source", try scope.get(owner, "envName"));
            try closeIterator(scope, owner);
            return flow.settle(scope.engine, owner, false, result);
        },
        .lazy => {
            const method = try scope.own(try v.js.getKey(scope.engine, value, try scope.get(owner, "method")));
            const arguments = try scope.get(owner, "arguments");
            const first = try v.at(scope, arguments, 0);
            const returned = if (try v.length(scope, arguments) == 1) try scope.call(method, value, &.{first}) else try scope.call(method, value, &.{ first, try v.at(scope, arguments, 1) });
            return flow.wait(continued, scope.engine, owner, returned, @intFromEnum(Stage.delegated));
        },
        .delegated => return flow.settle(scope.engine, owner, false, value),
        .file_module => {
            try scope.put(owner, "fs", value);
            const path = try scope.get(owner, "path");
            if (scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("~")}))) {
                const os = try osModule(scope);
                return flow.wait(continued, scope.engine, owner, os, @intFromEnum(Stage.file_os));
            }
            return accessFile(scope, owner, path);
        },
        .file_os => return accessFile(scope, owner, try scope.concat(try scope.invoke(value, "homedir", &.{}), try scope.invoke(try scope.get(owner, "path"), "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}))),
        .file_access => return flow.settle(scope.engine, owner, false, c.pi_js_bool(scope.engine.context, 1)),
    }
}
