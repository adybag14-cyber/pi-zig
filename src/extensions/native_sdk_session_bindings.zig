//! Ordinary AgentSession extension binding and discovered-resource bodies.
//! The live runner and resource loader are the session's actual objects; this
//! module neither substitutes discovery results nor creates a second runtime.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Method = enum(c_int) { bindExtensions, extendResourcesFromExtensions, buildExtensionResourcePaths, getExtensionSourceLabel };
const Stage = enum(c_int) { bound, extended, discovered };

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, engine.native_io orelse return error.NativeExtensionResourcesRequireIo);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = engine.native_module_values.get("node:path").?;
    // Source imports these bindings once; later namespace changes do not
    // replace the imported Node operations.
    var roots = [_]c.JSValue{ try scope.get(path, "basename"), try scope.get(path, "dirname") };
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, 1, field.value, roots.len, &roots)));
        if (method == .bindExtensions or method == .extendResourcesFromExtensions) {
            const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const input = if (argc > 0) argv[0] else c.pi_js_undefined();
    return (switch (@as(Method, @enumFromInt(magic))) {
        .bindExtensions => begin(engine, receiver, input, false),
        .extendResourcesFromExtensions => begin(engine, receiver, input, true),
        .buildExtensionResourcePaths => buildPaths(engine, receiver, input, roots[1]),
        .getExtensionSourceLabel => label(engine, input, roots[0]),
    }) catch |err| sdk.fail(engine, err);
}
fn synthetic(scope: *Scope, path: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("builtin:")})) or scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("<")}));
}
fn regex(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text(flags) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn label(engine: *em.Engine, path: c.JSValue, basename: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = if (try synthetic(&scope, path)) value: {
        const replace = try scope.get(path, "replace");
        break :value try scope.call(replace, path, &.{ try regex(&scope, "[<>]", "g"), try scope.text("") });
    } else value: {
        const base = try scope.call(basename, c.pi_js_undefined(), &.{path});
        const replace = try scope.get(base, "replace");
        break :value try scope.call(replace, base, &.{ try regex(&scope, "\\.(ts|js)$", ""), try scope.text("") });
    };
    return c.JS_DupValue(engine.context, try scope.concat(try scope.text("extension:"), try scope.stringify(name)));
}
fn buildPaths(engine: *em.Engine, session: c.JSValue, entries: c.JSValue, dirname: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const map = try scope.get(entries, "map");
    var roots = [_]c.JSValue{ session, dirname };
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, mapEntry, "", 1, 0, roots.len, &roots)));
    return c.JS_DupValue(engine.context, try scope.call(map, entries, &.{callback}));
}
fn mapEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return entry(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), roots[1]) catch |err| sdk.fail(engine, err);
}
fn entry(engine: *em.Engine, session: c.JSValue, input: c.JSValue, dirname: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const get_label = try scope.get(session, "getExtensionSourceLabel");
    const source = try scope.call(get_label, session, &.{try scope.get(input, "extensionPath")});
    const base_dir = if (try synthetic(&scope, try scope.get(input, "extensionPath"))) c.pi_js_undefined() else try scope.call(dirname, c.pi_js_undefined(), &.{try scope.get(input, "extensionPath")});
    const result = try scope.object();
    try scope.put(result, "path", try scope.get(input, "path"));
    const metadata = try scope.object();
    try scope.put(metadata, "source", source);
    try scope.put(metadata, "scope", try scope.text("temporary"));
    try scope.put(metadata, "origin", try scope.text("top-level"));
    try scope.put(metadata, "baseDir", base_dir);
    try scope.put(result, "metadata", metadata);
    return c.JS_DupValue(engine.context, result);
}
fn begin(engine: *em.Engine, session: c.JSValue, input: c.JSValue, discover: bool) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, input, discover) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, input: c.JSValue, discover: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    if (discover) {
        if (!scope.truthy(try scope.invoke(try scope.get(session, "_extensionRunner"), "hasHandlers", &.{try scope.text("resources_discover")}))) return flow.settle(engine, owner, false, c.pi_js_undefined());
        const runner = try scope.get(session, "_extensionRunner");
        const emit = try scope.get(runner, "emitResourcesDiscover");
        try flow.wait(step, engine, owner, try scope.call(emit, runner, &.{ try scope.get(session, "_cwd"), input }), @intFromEnum(Stage.discovered));
        return;
    }
    inline for (.{
        .{ "uiContext", "_extensionUIContext" },                         .{ "mode", "_extensionMode" },
        .{ "commandContextActions", "_extensionCommandContextActions" }, .{ "abortHandler", "_extensionAbortHandler" },
        .{ "shutdownHandler", "_extensionShutdownHandler" },             .{ "onError", "_extensionErrorListener" },
    }) |binding| {
        if (!c.JS_IsUndefined(try scope.get(input, binding[0]))) try scope.set(session, binding[1], try scope.get(input, binding[0]));
    }
    const apply = try scope.get(session, "_applyExtensionBindings");
    _ = try scope.call(apply, session, &.{try scope.get(session, "_extensionRunner")});
    const runner = try scope.get(session, "_extensionRunner");
    const emit = try scope.get(runner, "emit");
    try flow.wait(step, engine, owner, try scope.call(emit, runner, &.{try scope.get(session, "_sessionStartEvent")}), @intFromEnum(Stage.bound));
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    switch (@as(Stage, @enumFromInt(magic))) {
        .bound => {
            _ = try scope.invoke(try scope.get(session, "_extensionRunner"), "reportUnhandledMcpServers", &.{});
            const extend = try scope.get(session, "extendResourcesFromExtensions");
            const reason = if (scope.equal(try scope.get(try scope.get(session, "_sessionStartEvent"), "reason"), try scope.text("reload"))) "reload" else "startup";
            try flow.wait(step, engine, owner, try scope.call(extend, session, &.{try scope.text(reason)}), @intFromEnum(Stage.extended));
        },
        .extended => try flow.settle(engine, owner, false, c.pi_js_undefined()),
        .discovered => {
            const skills = try scope.get(value, "skillPaths");
            const prompts = try scope.get(value, "promptPaths");
            const themes = try scope.get(value, "themePaths");
            const zero = c.JS_NewInt32(engine.context, 0);
            if (scope.equal(try scope.get(skills, "length"), zero) and scope.equal(try scope.get(prompts, "length"), zero) and scope.equal(try scope.get(themes, "length"), zero)) return flow.settle(engine, owner, false, c.pi_js_undefined());
            const paths = try scope.object();
            try scope.put(paths, "skillPaths", try scope.invoke(session, "buildExtensionResourcePaths", &.{skills}));
            try scope.put(paths, "promptPaths", try scope.invoke(session, "buildExtensionResourcePaths", &.{prompts}));
            try scope.put(paths, "themePaths", try scope.invoke(session, "buildExtensionResourcePaths", &.{themes}));
            _ = try scope.invoke(try scope.get(session, "_resourceLoader"), "extendResources", &.{paths});
            const rebuild = try scope.get(session, "_rebuildSystemPrompt");
            _ = try scope.call(rebuild, session, &.{try scope.invoke(session, "getActiveToolNames", &.{})});
            try flow.settle(engine, owner, false, c.pi_js_undefined());
        },
    }
}
