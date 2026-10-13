//! Original session input interception and extension command dispatch. All
//! collaborators are read from ordinary live fields at their Source positions.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (.{ .{ "_runInputHandlers", 4, 0, true }, .{ "_tryExecuteExtensionCommand", 1, 1, true }, .{ "_expandSkillCommand", 1, 2, false } }) |spec| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, spec[0], spec[1], spec[2], 0, null));
        defer engine.freeValue(function);
        if (spec[3]) {
            const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(parent);
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, spec[0], c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn arg(argc: c_int, argv: [*c]c.JSValue, index: usize) c.JSValue {
    return if (index < @as(usize, @intCast(argc))) argv[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (magic == 2) return @import("native_sdk_skill_expansion.zig").expandSession(engine, receiver, arg(argc, argv, 0)) catch |err| sdk.fail(engine, err);
    const pending = flow.create(engine, receiver) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(pending.owner);
    if (magic == 0) {
        input(engine, pending.owner, .{ arg(argc, argv, 0), arg(argc, argv, 1), arg(argc, argv, 2), arg(argc, argv, 3) }) catch |err| {
            flow.rejectError(engine, pending.owner, err) catch |failure| {
                engine.freeValue(pending.promise);
                return sdk.fail(engine, failure);
            };
        };
    } else command(engine, pending.owner, arg(argc, argv, 0)) catch |err| {
        flow.rejectError(engine, pending.owner, err) catch |failure| {
            engine.freeValue(pending.promise);
            return sdk.fail(engine, failure);
        };
    };
    return pending.promise;
}
fn input(engine: *em.Engine, owner: c.JSValue, args: [4]c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "text", args[0]);
    try scope.put(owner, "images", args[1]);
    const session = try scope.get(owner, "agent");
    const runner = try scope.get(session, "_extensionRunner");
    if (!scope.truthy(try scope.invoke(runner, "hasHandlers", &.{try scope.text("input")}))) return returnInput(&scope, owner, args[0], args[1]);
    // Source reads _extensionRunner again after the hasHandlers call.
    const actual_runner = try scope.get(session, "_extensionRunner");
    const pending = try scope.invoke(actual_runner, "emitInput", &args);
    try flow.wait(inputComplete, engine, owner, pending, 0);
}
fn inputComplete(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.equal(try scope.get(value, "action"), try scope.text("handled"))) return flow.settle(engine, owner, false, c.pi_js_undefined());
    if (scope.equal(try scope.get(value, "action"), try scope.text("transform"))) {
        const text = try scope.get(value, "text");
        const images = try scope.get(value, "images");
        return returnInput(&scope, owner, text, if (temp.nullish(images)) try scope.get(owner, "images") else images);
    }
    return returnInput(&scope, owner, try scope.get(owner, "text"), try scope.get(owner, "images"));
}
fn returnInput(scope: *Scope, owner: c.JSValue, text: c.JSValue, images: c.JSValue) !void {
    const value = try scope.object();
    try scope.put(value, "text", text);
    try scope.put(value, "images", images);
    try flow.settle(scope.engine, owner, false, value);
}
fn command(engine: *em.Engine, owner: c.JSValue, text: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const index = try scope.invoke(text, "indexOf", &.{try scope.text(" ")});
    const absent = scope.equal(index, c.JS_NewInt32(engine.context, -1));
    const name = if (absent) try scope.invoke(text, "slice", &.{c.JS_NewInt32(engine.context, 1)}) else try scope.invoke(text, "slice", &.{ c.JS_NewInt32(engine.context, 1), index });
    const arguments = if (absent) try scope.text("") else tail: {
        const slice = try scope.get(text, "slice");
        const symbol = try scope.own(try engine.checked(c.JS_GetToPrimitiveSymbol(engine.context)));
        const start = try scope.own(try @import("native_tui_value_arithmetic.zig").add(engine, index, c.JS_NewInt32(engine.context, 1), symbol));
        break :tail try scope.call(slice, text, &.{start});
    };
    const session = try scope.get(owner, "agent");
    const runner = try scope.get(session, "_extensionRunner");
    const selected = try scope.invoke(runner, "getCommand", &.{name});
    if (!scope.truthy(selected)) return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    const context = try scope.invoke(try scope.get(session, "_extensionRunner"), "createCommandContext", &.{});
    try scope.put(owner, "commandName", name);
    const generation = engine.native_allocation_generation;
    const pending = scope.invoke(selected, "handler", &.{ arguments, context }) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        return commandComplete(engine, owner, reason, true, 0);
    };
    try flow.wait(commandComplete, engine, owner, pending, 0);
}
fn commandComplete(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        if (engine.native_allocation_exception) |fatal| {
            if (scope.equal(value, fatal)) return flow.settle(engine, owner, true, value);
        }
        const session = try scope.get(owner, "agent");
        const runner = try scope.get(session, "_extensionRunner");
        const callback = try scope.get(runner, "emitError");
        const event = try scope.object();
        try scope.put(event, "extensionPath", try scope.concat(try scope.text("command:"), try scope.stringify(try scope.get(owner, "commandName"))));
        try scope.put(event, "event", try scope.text("command"));
        try scope.put(event, "error", try scope.own(try errorMessage(engine, value)));
        _ = try scope.call(callback, runner, &.{event});
    }
    try flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 1));
}
pub fn errorMessage(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const constructor = try scope.get(global, "Error");
    const is_error = c.JS_IsInstanceOf(engine.context, value, constructor);
    if (is_error < 0) return js.capture(engine);
    if (is_error == 1) return sdk.get(engine, value, "message");
    const function = try scope.get(global, "String");
    return js.call(engine, function, c.pi_js_undefined(), &.{value});
}
