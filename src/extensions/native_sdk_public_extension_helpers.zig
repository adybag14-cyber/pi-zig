//! Actual c268 extension type guards and registered-tool adapters.
//! The same bodies supply the public index and genuine extension runners.
const x = @import("native_sdk_catalog_values.zig");
const c = x.c;
const Ops = x.Ops;
const Scope = x.Scope;
const cache_key = "\x00sdk-public-extension-helpers";
const Guard = struct { name: [*:0]const u8, tool: []const u8 };
const guards = [_]Guard{
    .{ .name = "isBashToolResult", .tool = "bash" },
    .{ .name = "isPowerShellToolResult", .tool = "powershell" },
    .{ .name = "isReadToolResult", .tool = "read" },
    .{ .name = "isEditToolResult", .tool = "edit" },
    .{ .name = "isWriteToolResult", .tool = "write" },
    .{ .name = "isGrepToolResult", .tool = "grep" },
    .{ .name = "isFindToolResult", .tool = "find" },
    .{ .name = "isLsToolResult", .tool = "ls" },
};
const definition_fields = .{ "name", "label", "description", "parameters", "outputSchema", "constrainedSampling", "prepareArguments", "executionMode" };
fn arg(args: []const c.JSValue, position: usize) c.JSValue { return if (position < args.len) args[position] else c.pi_js_undefined(); }

pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    const namespace = createOwned(engine) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, namespace));
}
fn createOwned(engine: *x.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    const namespace = try x.owned.finishValue(&s, createBody(&o));
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = x.owned.Completion.initValue(engine, err); completion.release(namespace);
        return completion.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, namespace));
    return namespace;
}
fn createBody(o: *Ops) !c.JSValue {
    const namespace = try o.object();
    try o.put(namespace, "defineTool", try o.callback("defineTool", 1, defineTool, &.{}, false));
    inline for (guards) |guard|
        try o.put(namespace, guard.name, try o.callback(guard.name, 1, toolResult, &.{try o.text(guard.tool)}, false));
    try o.put(namespace, "isToolCallEventType", try o.callback("isToolCallEventType", 2, toolCall, &.{}, false));
    try o.put(namespace, "wrapRegisteredTool", try o.callback("wrapRegisteredTool", 2, registeredTool, &.{}, false));
    try o.put(namespace, "wrapRegisteredTools", try o.callback("wrapRegisteredTools", 2, registeredTools, &.{}, false));
    return c.JS_DupValue(o.s.engine.context, namespace);
}
fn defineTool(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_DupValue(engine.context, arg(args, 0));
}
fn toolResult(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, guardBody(&o, arg(args, 0), roots[0]));
}
fn toolCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, guardBody(&o, arg(args, 1), arg(args, 0)));
}
fn guardBody(o: *Ops, event: c.JSValue, tool_name: c.JSValue) !c.JSValue {
    return c.pi_js_bool(o.s.engine.context, @intFromBool(o.equal(try o.get(event, "toolName"), tool_name)));
}
fn registeredTool(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return wrapRegistered(engine, arg(args, 0), arg(args, 1));
}
pub fn wrapRegistered(engine: *x.em.Engine, registered: c.JSValue, runner: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, wrapRegisteredBody(&o, registered, runner));
}
fn wrapRegisteredBody(o: *Ops, registered: c.JSValue, runner: c.JSValue) !c.JSValue {
    const definition = try o.get(registered, "definition");
    const context_factory = try o.callback("", 2, toolContext, &.{runner}, true);
    return wrapDefinition(o.s.engine, definition, context_factory);
}
/// The private Source wrapper is shared with the real tool-owner composition.
/// Optional context-factory calls and the live definition.execute lookup remain
/// part of the actual ordinary execute arrow.
pub fn wrapDefinition(engine: *x.em.Engine, definition: c.JSValue, context_factory: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, wrapDefinitionBody(&o, definition, context_factory));
}
fn wrapDefinitionBody(o: *Ops, definition: c.JSValue, context_factory: c.JSValue) !c.JSValue {
    const wrapped = try o.object();
    inline for (definition_fields) |field| try o.put(wrapped, field, try o.get(definition, field));
    try o.put(wrapped, "execute", try o.callback("execute", 5, execute, &.{ definition, context_factory }, true));
    return c.JS_DupValue(o.s.engine.context, wrapped);
}
fn toolContext(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, o.invokeOwned(roots[0], "createToolContext", &.{ arg(args, 0), arg(args, 1) }));
}
fn execute(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, executeBody(&o, args, roots[0], roots[1]));
}
fn executeBody(o: *Ops, args: []const c.JSValue, definition: c.JSValue, context_factory: c.JSValue) !c.JSValue {
    // Source resolves the execute callee before the nullish-context expression.
    const callable = try o.get(definition, "execute");
    const supplied_context = arg(args, 4);
    const context = if (!x.nullish(supplied_context)) supplied_context
        else if (x.nullish(context_factory)) c.pi_js_undefined()
        else try o.call(context_factory, c.pi_js_undefined(), &.{ arg(args, 0), arg(args, 2) });
    return c.JS_DupValue(o.s.engine.context, try o.call(callable, definition, &.{
        arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3), context,
    }));
}
fn registeredTools(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; var o: Ops = .{ .s = &s };
    return x.owned.finishValue(&s, registeredToolsBody(&o, arg(args, 0), arg(args, 1)));
}
fn registeredToolsBody(o: *Ops, registered: c.JSValue, runner: c.JSValue) !c.JSValue {
    const map = try o.get(registered, "map");
    const callback = try o.callback("", 1, mapRegistered, &.{runner}, true);
    return c.JS_DupValue(o.s.engine.context, try o.call(map, registered, &.{callback}));
}
fn mapRegistered(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return wrapRegistered(engine, arg(args, 0), roots[0]);
}
