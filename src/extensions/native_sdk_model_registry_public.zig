//! Actual c268 ModelRegistry public class and method bodies. The constructor
//! retains the real SDK instance/lease actor; methods read the public runtime
//! afresh and the two async methods use genuine native Await continuations.
const std = @import("std");
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = h.Engine;
const Scope = h.Scope;
const af = v.af;
const frames = @import("native_public_lexical_frame.zig");
const catalog = @import("native_sdk_catalog_values.zig");
const copy = @import("native_sdk_catalog_copy.zig");
const constructor_key = "pi-private:sdk-model-registry-constructor-c268";
const AuthFrame = frames.Frame(enum { resolution, compatibility, caught, cause, message });
const Method = enum(c_int) {
    refresh, getError, getAll, getAvailable, find, findOfType, hasConfiguredAuth,
    getApiKeyAndHeaders, getProviderAuthStatus, getProvider, stream, streamSimple,
    complete, getModelsOfType, getAvailableOfType, getModelOfType, classify,
    generateImages, getProviderDisplayName, getProviderAuth, getApiKeyForProvider,
    isUsingOAuth, registerProvider, unregisterProvider, registerVirtualModel,
    unregisterVirtualModel, getRegisteredProviderConfig, getRegisteredNativeProvider,
    getRegisteredProviderIds,
};
fn arity(which: Method) c_int {
    return switch (which) {
        .getError, .getAll, .getAvailable, .getRegisteredProviderIds => 0,
        .find, .getModelsOfType, .registerProvider, .unregisterVirtualModel => 2,
        .findOfType, .stream, .streamSimple, .complete, .getAvailableOfType,
        .getModelOfType, .classify, .generateImages => 3,
        else => 1,
    };
}
pub fn constructor(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    return h.duplicate(engine, engine.native_module_values.get(constructor_key) orelse
        return error.ActualModelRegistryConstructorNotInstalled);
}
pub fn createConstructor(engine: *Engine, prototype: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(constructor_key)) |known| return h.duplicate(engine, known);
    const candidate = try h.expression(engine, constructorBody, .{prototype});
    if (engine.native_module_values.get(constructor_key)) |known| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, known));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failure = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failure.release(candidate);
        return failure.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(constructor_key, candidate);
    return h.duplicate(engine, candidate);
}
fn constructorBody(s: *Scope, prototype: c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const value = try boundary.finishValue(s, @import("native_class.zig").constructor(
        s.engine, "ModelRegistry", 1, prototype, construct, &.{}));
    try installBody(s, prototype);
    return v.duplicate(s, value);
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, constructBody, .{ target, v.arg(args, 0) });
}
fn constructBody(s: *Scope, target: c.JSValue, runtime: c.JSValue) !c.JSValue {
    // This bridge performs the genuine GetPrototypeFromConstructor operation,
    // including the new target's realm when its prototype is primitive. The
    // following SDK allocation has its own non-guest producer qualification.
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const prototype = try boundary.finishValue(s,
        c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, target));
    return @import("native_sdk.zig").newModelRegistryWithPrototype(s.engine, runtime, prototype);
}
pub fn install(engine: *Engine, prototype: c.JSValue) !void {
    return h.statement(engine, installBody, .{prototype});
}
fn installBody(s: *Scope, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const which: Method = @enumFromInt(field.value);
        const roots = &.{c.JS_NewInt32(s.engine.context, @intCast(field.value))};
        const value = if (which == .getApiKeyAndHeaders or which == .getApiKeyForProvider) async_value: {
            var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
            break :async_value try boundary.finishValue(s,
                af.createResumable(s.engine, field.name, arity(which), authBody, roots));
        } else try v.method(s, field.name, arity(which), method, roots);
        var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
        try boundary.finishStatus(c.JS_DefinePropertyValueStr(s.engine.context, prototype,
            field.name, v.duplicate(s, value), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE));
    }
}
fn method(engine: *Engine, receiver: c.JSValue, supplied: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const which: Method = @enumFromInt(c.JS_VALUE_GET_INT(roots[0]));
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    const count: usize = @intCast(arity(which));
    for (args[0..count], 0..) |*slot, position| slot.* = v.arg(supplied, position);
    return h.expression(engine, methodBody, .{ receiver, which, args[0..count] });
}
fn runtimeCall(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const runtime = try v.get(s, receiver, "runtime");
    const callable = try v.get(s, runtime, name);
    return v.duplicate(s, try v.call(s, callable, runtime, args));
}
fn runtimeProviderCall(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, model: c.JSValue) !c.JSValue {
    const runtime = try v.get(s, receiver, "runtime");
    const callable = try v.get(s, runtime, name);
    const provider = try v.get(s, model, "provider");
    return v.duplicate(s, try v.call(s, callable, runtime, &.{provider}));
}
fn append(s: *Scope, array: c.JSValue, iterable: c.JSValue) !void {
    var position: u32 = 0;
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_PiArrayAppend(s.engine.context, array, &position, iterable));
}
fn snapshot(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const result = try v.array(s);
    const rows = try v.own(s, try h.expression(s.engine, runtimeCall, .{ receiver, name, @as([]const c.JSValue, &.{}) }));
    try append(s, result, rows);
    return v.duplicate(s, result);
}
fn providerName(s: *Scope, receiver: c.JSValue, provider: c.JSValue) !c.JSValue {
    const selected = try v.own(s, try h.expression(s.engine, runtimeCall,
        .{ receiver, @as([*:0]const u8, "getProvider"), @as([]const c.JSValue, &.{provider}) }));
    return v.duplicate(s, if (v.nullish(selected)) c.pi_js_undefined() else try v.get(s, selected, "name"));
}
fn displayName(s: *Scope, receiver: c.JSValue, provider: c.JSValue) !c.JSValue {
    const name = try v.own(s, try h.expression(s.engine, providerName, .{ receiver, provider }));
    return v.duplicate(s, if (v.nullish(name)) provider else name);
}
fn registrationError(s: *Scope) !c.JSValue {
    const error_constructor = try v.global(s, "Error");
    return v.duplicate(s, try v.construct(s, error_constructor,
        &.{try v.text(s, "Provider config is required when registering by name")}));
}
fn methodBody(s: *Scope, receiver: c.JSValue, which: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (which) {
        .getAll => return snapshot(s, receiver, "getModels"),
        .getAvailable => return snapshot(s, receiver, "getAvailableSnapshot"),
        .find => return runtimeCall(s, receiver, "getModel", args),
        .findOfType => return runtimeCall(s, receiver, "getModelOfType", args),
        .hasConfiguredAuth, .isUsingOAuth => return runtimeProviderCall(s, receiver, @tagName(which).ptr, first),
        .getProviderAuth => return runtimeCall(s, receiver, "getAuth", args),
        .getProviderDisplayName => return displayName(s, receiver, first),
        .registerProvider => {
            if (c.JS_IsString(first)) {
                if (!v.truthy(s, v.arg(args, 1))) {
                    const reason = try h.expression(s.engine, registrationError, .{});
                    return s.engine.checked(c.JS_Throw(s.engine.context, reason));
                }
                _ = try v.own(s, try h.expression(s.engine, runtimeCall,
                    .{ receiver, @as([*:0]const u8, "registerProvider"), args }));
            } else {
                _ = try v.own(s, try h.expression(s.engine, runtimeCall,
                    .{ receiver, @as([*:0]const u8, "registerNativeProvider"), @as([]const c.JSValue, &.{first}) }));
            }
            return c.pi_js_undefined();
        },
        .unregisterProvider, .registerVirtualModel, .unregisterVirtualModel => {
            _ = try v.own(s, try h.expression(s.engine, runtimeCall, .{ receiver, @tagName(which).ptr, args }));
            return c.pi_js_undefined();
        },
        .getApiKeyAndHeaders, .getApiKeyForProvider => unreachable,
        else => return runtimeCall(s, receiver, @tagName(which).ptr, args),
    }
}
fn attempt(engine: *Engine, comptime body: anytype, args: anytype) !af.Action {
    var s: Scope = .{ .engine = engine };
    const result: anyerror!af.Action = if (@call(.auto, body, .{&s} ++ args)) |value|
        .{ .returned = value } else |err| err;
    return v.owned.finishAction(&s, result);
}
fn initialize(s: *Scope, state: *c.JSValue) !*AuthFrame {
    const frame = try AuthFrame.create(s);
    af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
    return frame;
}
fn instanceError(s: *Scope, value: c.JSValue) !c.JSValue {
    const constructor_value = try v.global(s, "Error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const status = c.JS_IsInstanceOf(s.engine.context, value, constructor_value);
    try boundary.finishStatus(if (status < 0) status else 0);
    return v.boolean(s, status != 0);
}
fn isError(engine: *Engine, value: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, instanceError, .{value}));
}
fn globalString(s: *Scope, value: c.JSValue) !c.JSValue {
    const callable = try v.global(s, "String");
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{value}));
}
fn providerText(s: *Scope, model: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, model, "provider")));
}
fn missingText(s: *Scope, model: c.JSValue) !c.JSValue {
    const first = try v.text(s, "No API key found for \"");
    const rendered = try v.own(s, try h.expression(s.engine, providerText, .{model}));
    const prefix = try h.binary(s, .add, first, rendered);
    return v.duplicate(s, try h.binary(s, .add, prefix, try v.text(s, "\"")));
}
fn missingRecord(s: *Scope, model: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "ok", v.boolean(s, false));
    try v.put(s, result, "error", try v.own(s, try h.expression(s.engine, missingText, .{model})));
    return v.duplicate(s, result);
}
fn compatibilityRecord(s: *Scope, compatibility: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "ok", v.boolean(s, true));
    try v.put(s, result, "headers", try v.get(s, compatibility, "headers"));
    return v.duplicate(s, result);
}
fn baseUrlTest(s: *Scope, resolution: c.JSValue) !c.JSValue {
    const url = try v.own(s, try h.nested(s.engine, resolution, "auth", "baseUrl"));
    return v.boolean(s, v.truthy(s, url));
}
fn baseUrlSpread(s: *Scope, resolution: c.JSValue) !c.JSValue {
    const value = try v.object(s);
    try v.put(s, value, "baseUrl", try v.own(s, try h.nested(s.engine, resolution, "auth", "baseUrl")));
    return v.duplicate(s, value);
}
fn applyBaseUrl(s: *Scope, target: c.JSValue, resolution: c.JSValue, present: bool) !void {
    const value = if (present)
        try v.own(s, try h.expression(s.engine, baseUrlSpread, .{resolution}))
    else try v.object(s);
    var ops: catalog.Ops = .{ .s = s };
    try copy.into(&ops, target, value);
}
fn resolvedRecord(s: *Scope, resolution: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "ok", v.boolean(s, true));
    try v.put(s, result, "apiKey", try v.own(s, try h.nested(s.engine, resolution, "auth", "apiKey")));
    try v.put(s, result, "headers", try v.own(s, try h.nested(s.engine, resolution, "auth", "headers")));
    const present = h.truthy(s.engine, try h.expression(s.engine, baseUrlTest, .{resolution}));
    try h.statement(s.engine, applyBaseUrl, .{ result, resolution, present });
    try v.put(s, result, "env", try v.get(s, resolution, "env"));
    return v.duplicate(s, result);
}
fn afterHeaders(s: *Scope, frame: *AuthFrame, receiver: c.JSValue, model: c.JSValue, input: c.JSValue) !c.JSValue {
    try frame.copy(.resolution, input);
    if (!v.truthy(s, frame.get(.resolution))) {
        try frame.take(.compatibility, h.expression(s.engine, runtimeCall,
            .{ receiver, @as([*:0]const u8, "getCompatibilityRequestConfig"), @as([]const c.JSValue, &.{model}) }));
        if (try h.fieldTest(s.engine, frame.get(.compatibility), "authHeader", .truthy))
            return missingRecord(s, model);
        return compatibilityRecord(s, frame.get(.compatibility));
    }
    return resolvedRecord(s, frame.get(.resolution));
}
fn afterKey(s: *Scope, input: c.JSValue) !c.JSValue {
    return if (v.nullish(input)) c.pi_js_undefined() else h.nested(s.engine, input, "auth", "apiKey");
}
fn caughtRecord(s: *Scope, message: c.JSValue, model: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "ok", v.boolean(s, false));
    const selected = if (try v.eq(s, message, "authHeader requires a resolved API key"))
        try v.own(s, try h.expression(s.engine, missingText, .{model})) else message;
    try v.put(s, result, "error", selected);
    return v.duplicate(s, result);
}
fn catchHeaders(s: *Scope, frame: *AuthFrame, model: c.JSValue) !c.JSValue {
    try frame.take(.cause, if (try isError(s.engine, frame.get(.caught)))
        h.get(s.engine, frame.get(.caught), "cause") else c.pi_js_undefined());
    try frame.take(.message, if (try isError(s.engine, frame.get(.cause)))
        h.get(s.engine, frame.get(.cause), "message")
    else if (try isError(s.engine, frame.get(.caught)))
        h.get(s.engine, frame.get(.caught), "message")
    else h.expression(s.engine, globalString, .{frame.get(.caught)}));
    return caughtRecord(s, frame.get(.message), model);
}
fn catchReason(s: *Scope, frame: ?*AuthFrame, model: c.JSValue, reason: c.JSValue) !af.Action {
    if (frame) |locals| {
        try locals.take(.caught, reason);
        return .{ .returned = try catchHeaders(s, locals, model) };
    }
    var discarded = v.owned.Completion.initValue(s.engine, c.pi_js_undefined());
    discarded.release(reason);
    return .{ .returned = try discarded.finishValue() };
}
fn advance(s: *Scope, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue,
    state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action
{
    const headers = c.JS_VALUE_GET_INT(roots[0]) == @intFromEnum(Method.getApiKeyAndHeaders);
    const frame: ?*AuthFrame = if (!headers) null else if (completion == .start)
        try initialize(s, state) else AuthFrame.from(state.*);
    const model = v.arg(args, 0);
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(s.engine);
        return catchReason(s, frame, model, v.duplicate(s, input));
    }
    const outcome = if (completion == .start)
        try attempt(s.engine, runtimeCall, .{ receiver, @as([*:0]const u8, "getAuth"), @as([]const c.JSValue, &.{model}) })
    else if (frame) |locals|
        try attempt(s.engine, afterHeaders, .{ locals, receiver, model, input })
    else try attempt(s.engine, afterKey, .{input});
    return switch (outcome) {
        .returned => |value| if (completion == .start) .{ .awaited = value } else .{ .returned = value },
        .thrown => |reason| catchReason(s, frame, model, reason),
        .awaited => unreachable,
    };
}
fn authBody(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue,
    state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action
{
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, advance(&s, receiver, args, roots, state, completion, input));
}
