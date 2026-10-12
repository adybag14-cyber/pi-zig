//! Draft: durable's catalog globals over the invocation's actual Models service.
//! It does not load or certify a generated model catalog.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const vm = @import("native_values.zig");
const c = em.c;
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn concat(scope: *Scope, parts: []const c.JSValue) !c.JSValue {
    var value = try scope.text("");
    for (parts) |part| value = try scope.concat(value, part);
    return value;
}
fn fail(scope: *Scope, message: c.JSValue) anyerror {
    const reason = js.builtin(scope.engine, "Error", &.{message}) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, reason)) catch |err| return err;
    unreachable;
}
fn modelType(scope: *Scope, value: c.JSValue) !c.JSValue {
    inline for (.{ "chat", "image", "classifier" }) |kind| if (try is(scope, value, kind)) return value;
    return fail(scope, try concat(scope, &.{ try scope.text("Unknown model type "), try scope.invoke(try scope.global("JSON"), "stringify", &.{value}), try scope.text(". Use \"chat\", \"image\", or \"classifier\".") }));
}
fn provider(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return c.pi_js_undefined();
    if (!c.JS_IsString(value)) return fail(scope, try scope.text("provider must be a string"));
    return value;
}
fn describe(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return scope.stringify(value);
    if (c.JS_IsArray(value)) return scope.text(if (try vm.length(scope.engine, value) == 0) "an empty array" else "an array");
    if (c.JS_IsFunction(scope.engine.context, value)) return scope.text("a function");
    if (c.JS_IsObject(value)) {
        const keys = try scope.invoke(try scope.global("Object"), "keys", &.{value});
        const count = try vm.length(scope.engine, keys);
        if (count == 0) return scope.text("{}");
        const shown = try scope.invoke(keys, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 6) });
        return concat(scope, &.{ try scope.text("{ "), try scope.invoke(shown, "join", &.{try scope.text(", ")}), try scope.text(if (count > 6) ", ... }" else " }") });
    }
    return scope.text(if (c.JS_IsString(value)) "a string" else if (c.JS_IsBool(value)) "a boolean" else if (c.JS_IsNumber(value)) "a number" else if (c.JS_IsBigInt(value)) "a bigint" else "a symbol");
}
fn toInfo(scope: *Scope, model: c.JSValue) !c.JSValue {
    const copied = try scope.own(try js.spread(scope.engine, model));
    const atom = c.JS_NewAtom(scope.engine.context, "headers");
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DeleteProperty(scope.engine.context, copied, atom, c.JS_PROP_THROW) < 0) return js.capture(scope.engine);
    const json = try scope.global("JSON");
    return scope.invoke(json, "parse", &.{try scope.invoke(json, "stringify", &.{copied})});
}
fn mapInfo(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = toInfo(&scope, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.JS_DupValue(engine.context, value);
}
fn map(scope: *Scope, models: c.JSValue) !c.JSValue {
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, mapInfo, "toModelInfo", 1, 0, 0, null)));
    return scope.invoke(models, "map", &.{callback});
}
fn resolved(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer engine.freeValue(functions[0]);
    defer engine.freeValue(functions[1]);
    var args = [_]c.JSValue{value};
    const ignored = try engine.checked(c.JS_Call(engine.context, functions[0], c.pi_js_undefined(), 1, &args));
    engine.freeValue(ignored);
    return promise;
}
pub fn isCatalog(engine: *em.Engine, name: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "models.getModelsOfType", "models.getAvailableOfType", "models.getModelOfType" }) |value| if (try is(&scope, name, value)) return true;
    return false;
}
pub fn invoke(engine: *em.Engine, docs: c.JSValue, models: c.JSValue, context: c.JSValue, call: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = try scope.get(call, "name");
    const given = try scope.get(call, "args");
    const args = if (c.JS_IsArray(given)) given else try scope.array();
    const kind = try item(&scope, args, 0);
    const provider_id = try item(&scope, args, 1);
    const id = try item(&scope, args, 2);
    if (try is(&scope, name, "models.getModelsOfType")) return resolved(engine, try map(&scope, try scope.invoke(models, "getModelsOfType", &.{ try modelType(&scope, kind), try provider(&scope, provider_id) })));
    if (try is(&scope, name, "models.getAvailableOfType")) {
        const options = try scope.object();
        const signal = try scope.get(context, "abortSignal");
        if (!c.JS_IsUndefined(signal)) try scope.put(options, "signal", signal);
        const pending = try scope.invoke(models, "getAvailableOfType", &.{ try modelType(&scope, kind), try provider(&scope, provider_id), options });
        var captured: awaiting.Intrinsics = .{ .constructor = try scope.get(docs, "promiseConstructor"), .resolve = try scope.get(docs, "promiseResolve"), .then_function = try scope.get(docs, "promiseThen") };
        return awaiting.continueWith(available, engine, &captured, c.pi_js_undefined(), pending, 0);
    }
    if (!c.JS_IsString(provider_id) or !c.JS_IsString(id)) {
        const values = try scope.array();
        for (0..try vm.length(engine, args)) |i| _ = try scope.invoke(values, "push", &.{try describe(&scope, try item(&scope, args, i))});
        return fail(&scope, try concat(&scope, &.{ try scope.text("models.getModelOfType(type, provider, id) expects three strings, got ("), try scope.invoke(values, "join", &.{try scope.text(", ")}), try scope.text("). The provider and the id are separate arguments, for example models.getModelOfType(\"classifier\", \"typesafe\", \"jev-latest\").") }));
    }
    const model = try scope.invoke(models, "getModelOfType", &.{ try modelType(&scope, kind), provider_id, id });
    return resolved(engine, if (c.JS_IsUndefined(model)) c.pi_js_undefined() else try toInfo(&scope, model));
}
fn available(engine: *em.Engine, _: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try map(&scope, value));
}
