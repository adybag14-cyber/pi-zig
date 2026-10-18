//! Ordinary AgentSession extension binding and discovered-resource bodies.
//! The live runner and resource loader are the session's actual objects; this
//! module neither substitutes discovery results nor creates a second runtime.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_session_bindings_values.zig").Scope;
const owned = @import("native_sdk_owned_completion.zig");
const functions = @import("native_node_function.zig");
const af = @import("native_async_function.zig");
const body = @import("native_async_body.zig");
const c = em.c;
const Method = enum(c_int) { bindExtensions, extendResourcesFromExtensions, buildExtensionResourcePaths, getExtensionSourceLabel };
const Stage = enum(c_int) { bound, extended, discovered };

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    try engine.checkNativeEntry();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine };
    const result = owned.finishVoid(&scope, installBody(&scope, prototype));
    _ = try engine.checked(engine.leaveNativeInvocation(&invocation, if (result) |_| c.pi_js_undefined() else |err| @import("native_sdk.zig").fail(engine, err)));
}
fn installBody(scope: *Scope, prototype: c.JSValue) !void {
    const engine = scope.engine;
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, engine.native_io orelse return error.NativeExtensionResourcesRequireIo);
    const path = engine.native_module_values.get("node:path").?;
    // Source imports these bindings once; later namespace changes do not
    // replace the imported Node operations.
    const roots = [_]c.JSValue{ try scope.get(path, "basename"), try scope.get(path, "dirname") };
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        // Genuine AF owns its outer Promise and actual Await operations. The
        // ordinary methods and map callback remain ordinary nonconstructors.
        const function = try scope.own(switch (method) {
            .bindExtensions => try af.createResumable(engine, field.name, 1, bindBody, &.{}),
            .extendResourcesFromExtensions => try af.createResumable(engine, field.name, 1, discoverBody, &.{}),
            .buildExtensionResourcePaths => try functions.createMethod(engine, field.name, 1, pathsCallback, &roots),
            .getExtensionSourceLabel => try functions.createMethod(engine, field.name, 1, labelCallback, &roots),
        });
        const generation = engine.native_allocation_generation;
        try scope.status(c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE), generation);
    }
}
fn arg(args: []const c.JSValue) c.JSValue { return if (args.len > 0) args[0] else c.pi_js_undefined(); }
fn pathsCallback(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, buildPaths(&scope, receiver, arg(args), roots[1]));
}
fn labelCallback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, label(&scope, arg(args), roots[0]));
}
fn synthetic(scope: *Scope, path: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("builtin:")})) or scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("<")}));
}
fn regex(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text(flags) };
    const generation = scope.engine.native_allocation_generation;
    return scope.own(try scope.raw(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args), generation));
}
fn label(scope: *Scope, path: c.JSValue, basename: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const name = if (try synthetic(scope, path)) value: {
        const replace = try scope.get(path, "replace");
        break :value try scope.call(replace, path, &.{ try regex(scope, "[<>]", "g"), try scope.text("") });
    } else value: {
        const base = try scope.call(basename, c.pi_js_undefined(), &.{path});
        const replace = try scope.get(base, "replace");
        break :value try scope.call(replace, base, &.{ try regex(scope, "\\.(ts|js)$", ""), try scope.text("") });
    };
    return c.JS_DupValue(engine.context, try scope.concat(try scope.text("extension:"), try scope.stringify(name)));
}
fn buildPaths(scope: *Scope, session: c.JSValue, entries: c.JSValue, dirname: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const map = try scope.get(entries, "map");
    const roots = [_]c.JSValue{ session, dirname };
    const callback = try scope.own(try functions.createArrow(engine, "", 1, mapEntry, &roots));
    return c.JS_DupValue(engine.context, try scope.call(map, entries, &.{callback}));
}
fn mapEntry(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return owned.finishValue(&scope, entry(&scope, roots[0], arg(args), roots[1]));
}
fn entry(scope: *Scope, session: c.JSValue, input: c.JSValue, dirname: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const get_label = try scope.get(session, "getExtensionSourceLabel");
    const source = try scope.call(get_label, session, &.{try scope.get(input, "extensionPath")});
    const base_dir = if (try synthetic(scope, try scope.get(input, "extensionPath"))) c.pi_js_undefined() else try scope.call(dirname, c.pi_js_undefined(), &.{try scope.get(input, "extensionPath")});
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
// Private stage only: the genuine AF frame already retains receiver/arguments.
// No flow owner, Promise capability or reaction callback is manufactured here.
fn wait(scope: *Scope, state: *c.JSValue, value: c.JSValue, next: Stage) !af.Action {
    const engine = scope.engine;
    var job = state.*;
    if (c.JS_IsUndefined(job)) {
        const generation = engine.native_allocation_generation;
        job = try scope.own(try scope.raw(c.JS_NewObjectProto(engine.context, c.pi_js_null()), generation));
        af.replaceState(engine, state, c.JS_DupValue(engine.context, job));
    }
    try scope.put(job, "stage", c.JS_NewInt32(engine.context, @intFromEnum(next)));
    return .{ .awaited = c.JS_DupValue(engine.context, value) };
}
fn stage(scope: *Scope, state: c.JSValue) !Stage {
    // This is a private null-prototype integer written solely by wait().
    const value = try scope.get(state, "stage");
    var number: i32 = 0;
    const generation = scope.engine.native_allocation_generation;
    try scope.status(c.JS_ToInt32(scope.engine.context, &number, value), generation);
    return @enumFromInt(number);
}
fn bindBody(engine: *em.Engine, session: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    // Await rejection is completion DATA. Actual pending wins before ANY stage
    // read; no flags/private tags on input are consulted or reclassified.
    if (completion == .rejected) {
        try body.enterRejectedContinuation(engine);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    var scope: Scope = .{ .engine = engine };
    return owned.finishAction(&scope, bindStep(&scope, session, arg(args), state, completion));
}
fn bindStep(scope: *Scope, session: c.JSValue, bindings: c.JSValue, state: *c.JSValue, completion: af.Completion) !af.Action {
    if (completion == .start) {
        inline for (.{
            .{ "uiContext", "_extensionUIContext" }, .{ "mode", "_extensionMode" },
            .{ "commandContextActions", "_extensionCommandContextActions" }, .{ "abortHandler", "_extensionAbortHandler" },
            .{ "shutdownHandler", "_extensionShutdownHandler" }, .{ "onError", "_extensionErrorListener" },
        }) |binding| {
            // Source tests then evaluates the property AGAIN for assignment.
            if (!c.JS_IsUndefined(try scope.get(bindings, binding[0]))) try scope.set(session, binding[1], try scope.get(bindings, binding[0]));
        }
        const apply = try scope.get(session, "_applyExtensionBindings");
        _ = try scope.call(apply, session, &.{try scope.get(session, "_extensionRunner")});
        const runner = try scope.get(session, "_extensionRunner");
        const emit = try scope.get(runner, "emit");
        return wait(scope, state, try scope.call(emit, runner, &.{try scope.get(session, "_sessionStartEvent")}), .bound);
    }
    switch (try stage(scope, state.*)) {
        .bound => {
            _ = try scope.invoke(try scope.get(session, "_extensionRunner"), "reportUnhandledMcpServers", &.{});
            // Source captures the callee before evaluating reason's live getter.
            const extend = try scope.get(session, "extendResourcesFromExtensions");
            const reason = if (scope.equal(try scope.get(try scope.get(session, "_sessionStartEvent"), "reason"), try scope.text("reload"))) "reload" else "startup";
            return wait(scope, state, try scope.call(extend, session, &.{try scope.text(reason)}), .extended);
        },
        .extended => return .{ .returned = c.pi_js_undefined() },
        .discovered => unreachable,
    }
}
fn discoverBody(engine: *em.Engine, session: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    if (completion == .rejected) {
        try body.enterRejectedContinuation(engine);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    var scope: Scope = .{ .engine = engine };
    return owned.finishAction(&scope, discoverStep(&scope, session, arg(args), state, completion, input));
}
fn discoverStep(scope: *Scope, session: c.JSValue, reason: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const handlers_runner = try scope.get(session, "_extensionRunner");
        const has_handlers = try scope.get(handlers_runner, "hasHandlers");
        if (!scope.truthy(try scope.call(has_handlers, handlers_runner, &.{try scope.text("resources_discover")}))) return .{ .returned = c.pi_js_undefined() };
        const runner = try scope.get(session, "_extensionRunner");
        const emit = try scope.get(runner, "emitResourcesDiscover");
        return wait(scope, state, try scope.call(emit, runner, &.{ try scope.get(session, "_cwd"), reason }), .discovered);
    }
    if (try stage(scope, state.*) != .discovered) unreachable;
    // Destructuring reads all three in order before any length short circuit.
    const skills = try scope.get(input, "skillPaths");
    const prompts = try scope.get(input, "promptPaths");
    const themes = try scope.get(input, "themePaths");
    const zero = c.JS_NewInt32(scope.engine.context, 0);
    if (scope.equal(try scope.get(skills, "length"), zero) and scope.equal(try scope.get(prompts, "length"), zero) and scope.equal(try scope.get(themes, "length"), zero)) return .{ .returned = c.pi_js_undefined() };
    const paths = try scope.object();
    try scope.put(paths, "skillPaths", try scope.invoke(session, "buildExtensionResourcePaths", &.{skills}));
    try scope.put(paths, "promptPaths", try scope.invoke(session, "buildExtensionResourcePaths", &.{prompts}));
    try scope.put(paths, "themePaths", try scope.invoke(session, "buildExtensionResourcePaths", &.{themes}));
    _ = try scope.invoke(try scope.get(session, "_resourceLoader"), "extendResources", &.{paths});
    const rebuild = try scope.get(session, "_rebuildSystemPrompt");
    _ = try scope.call(rebuild, session, &.{try scope.invoke(session, "getActiveToolNames", &.{})});
    return .{ .returned = c.pi_js_undefined() };
}
