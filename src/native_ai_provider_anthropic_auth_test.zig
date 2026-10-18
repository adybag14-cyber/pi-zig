//! Prepared Source-only actual Anthropic auth factory and owner request controls.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
const dispatch = @import("extensions/native_ai_provider_auth_methods.zig");
fn publish(engine: *x.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn prepare(engine: *x.em.Engine) !void {
    const auth = try dispatch.create(engine, .anthropic); defer engine.freeValue(auth); try publish(engine, "actualAnthropicAuth", auth);
}
fn run(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/anthropic-api-key-genuine-af-observer.mjs"), "\n", tail }); defer engine.gpa.free(source);
    const namespace = try engine.evalModule(source, "actual-anthropic-api-key-caller.mjs"); engine.freeValue(namespace);
}
test "Anthropic actual auth genuine AF metadata and stored credential zero Await" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const auth = try s.global("actualAnthropicAuth");
    inline for (.{ "login", "resolve" }) |name| {
        const function = try s.get(auth, name); try std.testing.expect(c.JS_IsAsyncFunction(function));
        try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
        try std.testing.expect(s.equal(try s.get(function, "name"), try s.text(name)));
        try std.testing.expect(s.equal(try s.get(function, "length"), c.JS_NewInt32(engine.context, 1)));
    }
    const pending = try s.own(try engine.eval("actualAnthropicAuth.resolve({credential:{key:'owned'},signal:{throwIfAborted(){}}})", "actual-anthropic-zero-await.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
}
test "Anthropic actual auth genuine AF original caller priority getter abort and exact env Await paths" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try run(engine, "export const rows=await observeAnthropicApiKey(actualAnthropicAuth);if(rows.length!==9)throw Error('all actual auth branches');");
}
test "Anthropic actual auth genuine AF live literal iterators inherited setter and Source close precedence" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try run(engine, "export const rows=await observeAnthropicIterators(actualAnthropicAuth);");
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?); _ = engine.throwNativeOutOfMemory(); return c.JS_GetException(context);
}
fn actualB(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?); _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch {};
    const global = c.JS_GetGlobalObject(context); defer engine.freeValue(global);
    _ = c.JS_DefinePropertyValueStr(context, global, "observedActualB", c.JS_DupValue(context, engine.captured_exception.?), c.JS_PROP_C_W_E);
    return c.pi_js_undefined();
}
fn rawRead(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
test "Anthropic actual auth SAME env call DATA A remains ordinary while actual B1 wins exact reason" {
    inline for (.{ false, true }) |fatal| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        try engine.bindFunction("actualPrivateData", privateData, 0); try engine.bindFunction("actualB", actualB, 0);
        const prefix = "globalThis.authA=undefined;globalThis.authCaught=undefined;try{await actualAnthropicAuth.resolve({signal:{throwIfAborted(){}},ctx:{env(){authA=actualPrivateData();";
        const source = try std.mem.concat(engine.gpa, u8, &.{ prefix, if (fatal) "actualB();" else "", "throw authA}}})}catch(error){authCaught=error}export const completed=true;" }); defer engine.gpa.free(source);
        const outcome = engine.evalModule(source, "actual-anthropic-current-vs-data.mjs");
        if (fatal) {
            if (outcome) |value| { engine.freeValue(value); return error.ActualAnthropicFatalWasSwallowed; } else |err| try std.testing.expect(err == error.JavaScriptException);
            const chosen = engine.captured_exception orelse return error.RequiredActualAnthropicFatal;
            const b = try rawRead(engine, "observedActualB"); defer engine.freeValue(b); const a = try rawRead(engine, "authA"); defer engine.freeValue(a);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, chosen, b)); try std.testing.expect(!c.JS_IsStrictEqual(engine.context, a, b));
        } else {
            const value = try outcome; engine.freeValue(value);
            const a = try rawRead(engine, "authA"); defer engine.freeValue(a); const caught = try rawRead(engine, "authCaught"); defer engine.freeValue(caught);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, caught)); try std.testing.expect(!c.JS_IsUncatchableError(a));
        }
        try std.testing.expect(engine.native_fatal_invocation == null); try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { c.JS_RunGC(x.em.Engine.fromContext(context.?).runtime); return c.pi_js_undefined(); }
test "Anthropic actual auth prior job iterator step and env name retire before actual downstream callbacks" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine); try engine.bindFunction("actualGc", gc, 0);
    const seed = try engine.evalModule(
        \\let name={owned:'name'},step={done:false,get value(){const result=name;name=undefined;return result}};
        \\globalThis.anthropicNameWeak=new WeakRef(name);globalThis.anthropicStepWeak=new WeakRef(step);
        \\globalThis.takeAnthropicStep=()=>{const result=step;step=undefined;return result};
        \\let firstKey={owned:'truthy condition'};globalThis.anthropicFirstKeyWeak=new WeakRef(firstKey);
        \\globalThis.takeAnthropicFirstKey=()=>{const result=firstKey;firstKey=undefined;return result};
    , "actual-anthropic-prior-job.mjs"); engine.freeValue(seed); c.JS_ClearKeptObjects(engine.runtime);
    try run(engine,
        \\const original=Array.prototype[Symbol.iterator];let count=0;
        \\try{Array.prototype[Symbol.iterator]=function(){if(this[0]!=='ANTHROPIC_OAUTH_TOKEN')return original.call(this);return{next(){if(count++===0)return takeAnthropicStep();actualGc();if(anthropicNameWeak.deref()!==undefined)throw Error('previous envVar retained');return{done:true}}}};
        \\await actualAnthropicAuth.resolve({signal:{throwIfAborted(){}},ctx:{env(name){if(typeof name==='object'){actualGc();if(anthropicStepWeak.deref()!==undefined)throw Error('IteratorStep result retained')}return undefined}}});
        \\}finally{Array.prototype[Symbol.iterator]=original}
        \\let keyReads=0;await actualAnthropicAuth.resolve({ctx:{},signal:{throwIfAborted(){}},credential:{get key(){if(keyReads++===0)return takeAnthropicFirstKey();actualGc();if(anthropicFirstKeyWeak.deref()!==undefined)throw Error('condition key retained into second getter');return'owned-stored'}}});
    );
}
/// The real API owner supplies its complete native provider-constructor
/// namespace, genuine Models instance with real credential store/AuthContext,
/// and actual request context/options. No fake API/Models/HTTP is installed.
pub fn verifyActualProviderRequest(engine: *x.em.Engine, actual_provider_factories: c.JSValue, actual_models: c.JSValue, actual_context: c.JSValue, actual_options: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const factory = try s.get(actual_provider_factories, "anthropicProvider");
    const provider = try s.call(factory, c.pi_js_undefined(), &.{});
    const auth = try s.get(try s.get(provider, "auth"), "apiKey");
    inline for (.{ "login", "resolve" }) |name| try std.testing.expect(c.JS_IsAsyncFunction(try s.get(auth, name)));
    try publish(engine, "actualAnthropicProvider", provider); try publish(engine, "actualAnthropicModels", actual_models); try publish(engine, "actualAnthropicRequestContext", actual_context); try publish(engine, "actualAnthropicRequestOptions", actual_options);
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/anthropic-api-key-genuine-af-observer.mjs"), "\nexport const observation=await observeActualAnthropicRequest(actualAnthropicProvider,actualAnthropicModels,actualAnthropicRequestContext,actualAnthropicRequestOptions);" }); defer engine.gpa.free(source);
    return engine.evalModule(source, "actual-anthropic-provider-request.mjs");
}
fn actualRequestAnchor(engine: *x.em.Engine, factories: c.JSValue, models: c.JSValue, context: c.JSValue, options: c.JSValue) callconv(.c) c.JSValue {
    return verifyActualProviderRequest(engine, factories, models, context, options) catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
comptime { @export(&actualRequestAnchor, .{ .name = "anthropic_auth_actual_provider_request_control" }); }
