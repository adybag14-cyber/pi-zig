//! Public runner contexts root the real runner and captured model callables.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
const Field = enum(c_int) { ui, mode, hasUI, cwd, sessionManager, modelRegistry, model, scopedModels, thinkingLevel, isIdle, isProjectTrusted, signal, abort, hasPendingMessages, shutdown, getContextUsage, compact, getSystemPrompt, getSystemPromptOptions, waitForIdle, newSession, fork, navigateTree, switchSession, reload };
pub fn create(engine: *em.Engine, runner: c.JSValue, command: bool) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const model = try sdk.get(engine, runner, "getModel");
    defer engine.freeValue(model);
    const scoped = try sdk.get(engine, runner, "getScopedModels");
    defer engine.freeValue(scoped);
    var roots = [_]c.JSValue{ runner, model, scoped };
    inline for (std.meta.fields(Field)) |field| {
        const kind: Field = @enumFromInt(field.value);
        const extra = field.value >= @intFromEnum(Field.getSystemPromptOptions);
        if (!extra or command) {
            const getter = switch (kind) {
                .ui, .mode, .hasUI, .cwd, .sessionManager, .modelRegistry, .model, .scopedModels, .thinkingLevel, .signal => true,
                else => false,
            };
            const arity: c_int = switch (kind) {
                .compact, .newSession => 1,
                .fork, .navigateTree, .switchSession => 2,
                else => 0,
            };
            const name = if (getter) "get " ++ field.name else if (extra) "" else field.name;
            const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, arity, field.value, roots.len, &roots));
            if (getter) {
                const atom = c.JS_NewAtom(engine.context, field.name);
                defer c.JS_FreeAtom(engine.context, atom);
                if (c.JS_DefinePropertyGetSet(engine.context, result, atom, function, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
            } else try sdk.put(engine, result, field.name, function);
        }
    }
    return result;
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return value(engine, roots, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn value(engine: *em.Engine, roots: [*c]c.JSValue, kind: Field, args: []const c.JSValue) !c.JSValue {
    const checked = try js.invoke(engine, roots[0], "assertActive", &.{});
    engine.freeValue(checked);
    switch (kind) {
        .ui => return sdk.get(engine, roots[0], "uiContext"),
        .mode, .cwd, .sessionManager, .modelRegistry => return sdk.get(engine, roots[0], @tagName(kind)),
        .hasUI => return js.invoke(engine, roots[0], "hasUI", &.{}),
        .model, .scopedModels => return js.call(engine, roots[if (kind == .model) 1 else 2], c.pi_js_undefined(), &.{}),
        .thinkingLevel => {
            const runtime = try sdk.get(engine, roots[0], "runtime");
            defer engine.freeValue(runtime);
            return js.invoke(engine, runtime, "getThinkingLevel", &.{});
        },
        else => {
            const name: [*:0]const u8 = switch (kind) {
                .isIdle => "isIdleFn",
                .isProjectTrusted => "isProjectTrustedFn",
                .signal => "getSignalFn",
                .abort => "abortFn",
                .hasPendingMessages => "hasPendingMessagesFn",
                .shutdown => "shutdownHandler",
                .getContextUsage => "getContextUsageFn",
                .compact => "compactFn",
                .getSystemPrompt => "getSystemPromptFn",
                .getSystemPromptOptions => "getSystemPromptOptionsFn",
                .waitForIdle => "waitForIdleFn",
                .newSession => "newSessionHandler",
                .fork => "forkHandler",
                .navigateTree => "navigateTreeHandler",
                .switchSession => "switchSessionHandler",
                .reload => "reloadHandler",
                else => unreachable,
            };
            const count: usize = switch (kind) {
                .compact, .newSession => 1,
                .fork, .navigateTree, .switchSession => 2,
                else => 0,
            };
            var forwarded = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
            for (0..@min(count, args.len)) |index| forwarded[index] = args[index];
            const result = try js.invoke(engine, roots[0], name, forwarded[0..count]);
            if (kind == .abort or kind == .shutdown or kind == .compact) {
                engine.freeValue(result);
                return c.pi_js_undefined();
            }
            return result;
        },
    }
}
