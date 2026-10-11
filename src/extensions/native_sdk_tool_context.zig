//! VM-traced tool contexts retain their actual SDK session and original lease.
//! No Main extension binding or serialized context snapshot is involved.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
const Field = enum(c_int) { ui, mode, hasUI, cwd, sessionManager, modelRegistry, model, scopedModels, thinkingLevel, isIdle, isProjectTrusted, signal, abort, hasPendingMessages, shutdown, getContextUsage, compact, getSystemPrompt, tools, executeTool };
pub fn create(engine: *em.Engine, session: c.JSValue, generation: c.JSValue, runtime_id: c.JSValue, tool_call_id: c.JSValue, default_signal: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    var data = [_]c.JSValue{ session, generation, runtime_id, tool_call_id, default_signal };
    inline for (std.meta.fields(Field)) |field| {
        const kind: Field = @enumFromInt(field.value);
        const getter = switch (kind) {
            .ui, .mode, .hasUI, .cwd, .sessionManager, .modelRegistry, .model, .scopedModels, .thinkingLevel, .signal, .tools => true,
            else => false,
        };
        const flags: c_int = if (kind == .tools or kind == .executeTool) 0 else c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE;
        const arity: c_int = if (kind == .executeTool) 2 else if (kind == .compact) 1 else 0;
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, field.name, arity, field.value, data.len, &data));
        if (getter) {
            const atom = c.JS_NewAtom(engine.context, field.name);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, result, atom, function, c.pi_js_undefined(), flags) < 0) return error.JavaScriptException;
        } else if (c.JS_DefinePropertyValueStr(engine.context, result, field.name, function, flags | (if (kind == .executeTool) @as(c_int, 0) else c.JS_PROP_WRITABLE)) < 0) return error.JavaScriptException;
    }
    return result;
}
fn originalOwner(engine: *em.Engine, data: [*c]c.JSValue) !*sdk.State {
    const owner = sdk.state(engine, data[0]) catch return stale(engine);
    const actual = sdk.sessionModelLease(owner) catch return stale(engine);
    var generation: u64 = 0;
    var runtime_id: u64 = 0;
    if (c.JS_ToBigUint64(engine.context, &generation, data[1]) < 0 or c.JS_ToBigUint64(engine.context, &runtime_id, data[2]) < 0) return error.JavaScriptException;
    if (generation != actual.generation or runtime_id != actual.runtime_id or try @import("native_sdk_resource_owners.zig").sessionScopeRetired(owner)) return stale(engine);
    return owner;
}
fn stale(engine: *em.Engine) anyerror {
    @import("native_async_scope.zig").throwMessage(engine, @import("native_context_lifetime.zig").default_message) catch |err| return err;
    return error.JavaScriptException;
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return value(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| sdk.fail(engine, err);
}
fn value(engine: *em.Engine, field: Field, _: []c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const owner = try originalOwner(engine, data);
    const ui = @import("native_sdk_ui_context.zig");
    switch (field) {
        .ui => return ui.current(engine, data[0]),
        .mode => return ui.mode(engine, data[0]),
        .hasUI => return c.pi_js_bool(engine.context, @intFromBool(try ui.hasUI(engine, data[0]))),
        .cwd => return sdk.get(engine, owner.data, "_sdkToolCwd"),
        .sessionManager => return sdk.publicField(owner, "sessionManager"),
        .modelRegistry => return sdk.get(engine, owner.data, "modelRegistry"),
        .model => return sdk.agentField(owner, "model"),
        .thinkingLevel => return sdk.agentField(owner, "thinkingLevel"),
        .scopedModels => return sdk.get(engine, owner.data, "scopedModels"),
        .signal => return sdk.get(engine, owner.data, "promptSignal"),
        .isIdle => return c.pi_js_bool(engine.context, @intFromBool(!owner.running)),
        .isProjectTrusted => {
            const settings = try sdk.publicField(owner, "settingsManager");
            defer engine.freeValue(settings);
            return sdk.invoke(engine, settings, "isProjectTrusted", &.{});
        },
        .abort, .shutdown => {
            try ui.action(engine, data[0], field == .abort);
            return c.pi_js_undefined();
        },
        .hasPendingMessages => {
            const count = try sdk.get(engine, data[0], "pendingMessageCount");
            defer engine.freeValue(count);
            var number: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &number, count) < 0) return error.JavaScriptException;
            return c.pi_js_bool(engine.context, @intFromBool(number > 0));
        },
        .getSystemPrompt => return sdk.get(engine, owner.data, "systemPrompt"),
        .tools => return @import("native_sdk_tool_catalog.zig").callableDefinitions(owner),
        // These methods deliberately expose the existing SDK execution gaps.
        // Their real public session implementations can be reused once ported;
        // an absent implementation must not succeed as an invented no-op.
        .getContextUsage => return sdk.invoke(engine, data[0], "getContextUsage", &.{}),
        .compact => return error.NativeSDKCompactionUnavailable,
        .executeTool => return error.NativeSDKNestedToolExecutionUnavailable,
    }
}
