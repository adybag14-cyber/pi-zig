//! Prepared actual native algorithm/ownership controls; no jiti facade/default
//! SDK bootstrap is created. Integration entries require actual composed inputs.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const js = v.js;
const interop = @import("extensions/native_jiti_interop.zig");
const cache = @import("extensions/native_jiti_module_cache.zig");
const adapter = @import("extensions/native_extension_import_adapter.zig");
fn install(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn hook(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return hookBody(engine, args, roots[0]) catch |err| return interop.callbackFailure(engine, err, generation);
}
fn hookBody(engine: *v.em.Engine, args: []const c.JSValue, kind: c.JSValue) !c.JSValue {
    var code: i32 = 0;
    if (c.JS_ToInt32(engine.context, &code, kind) < 0) return js.capture(engine);
    return switch (code) {
        0 => interop.interopDefault(engine, arg(args, 0)),
        1 => interop.jsonSelfDefault(engine, arg(args, 0)),
        2 => interop.importDefault(engine, arg(args, 0), arg(args, 1)),
        3 => blk: { if (engine.captured_exception != null) return error.JitiHandledReasonStillCaptured; break :blk c.pi_js_undefined(); },
        else => error.InvalidJitiControlHook,
    };
}
fn installHooks(engine: *v.em.Engine) !void {
    inline for (.{ "NativeJitiInterop", "NativeJitiJSON", "NativeJitiDefault", "assertJitiCaptureEmpty" }, 0..) |name, index| {
        const function = try @import("extensions/native_node_function.zig").create(engine, name, if (index == 2) 2 else if (index == 3) 0 else 1, hook, &.{c.JS_NewInt32(engine.context, @intCast(index))});
        defer engine.freeValue(function);
        try install(engine, name, function);
    }
}
pub fn verifyProxyCacheAndReceivers(engine: *v.em.Engine) !void {
    try installHooks(engine);
    const result = try engine.evalModule(
        \\let reads=0;const key=Symbol('property'),def={method(){return this},get value(){reads++;return reads}},mod={default:def,own:'first'};
        \\Object.defineProperty(def,key,{get(){reads++;return reads}});const proxy=NativeJitiInterop(mod);
        \\if(proxy.__esModule!==true||proxy.default!==def||proxy.method()!==def||proxy.method!==proxy.method)throw Error('interop receiver/default');
        \\if(proxy.value!==1||proxy.value!==1||proxy[key]!==2||proxy[key]!==2||reads!==2)throw Error('interop string/symbol cache');
        \\if(proxy.own!=='first')throw Error('own read');mod.own='second';if(proxy.own!=='first')throw Error('target cached value');
        \\if(proxy.absent!==undefined)throw Error('missing first');def.absent='late';if(proxy.absent!==undefined)throw Error('missing cached undefined');
        \\const original=function(){return'original'},different=function(){return'default'};original.default=different;const callable=NativeJitiInterop(original);
        \\if(typeof callable!=='function'||callable()!=='original'||callable.default!==different)throw Error('callable target stays original');
        \\const noncallable=NativeJitiInterop({default:different});let error;try{noncallable()}catch(e){error=e}if(!(error instanceof TypeError)||NativeJitiDefault(noncallable,{default:true})!==different)throw Error('apply trap must not fabricate callability');
        \\const promise=Promise.resolve(1);if(NativeJitiInterop(promise)!==promise)throw Error('Promise passthrough');
        \\error=undefined;try{NativeJitiInterop({default:null}).missing}catch(e){error=e}if(!(error instanceof TypeError))throw Error('null default fallback');assertJitiCaptureEmpty();
        \\const trace=[],a=()=>1,b=()=>2,nested={get default(){trace.push('nested');return trace.length===1?a:b}},outer={default:nested,get __esModule(){trace.push('marker');return true}};
        \\const wrapped=NativeJitiInterop(outer);if(wrapped.default!==b||wrapped.default!==b||trace.join()!=='nested,marker,nested')throw Error('nested default double getter/cache');
        \\export const passed=true;
    , "jiti-interop-proxy-cache-receivers.mjs");
    defer engine.freeValue(result);
}
pub fn verifyRawReasonsAndJSON(engine: *v.em.Engine) !void {
    try installHooks(engine);
    const result = try engine.evalModule(
        \\const reason={trap:true},target=new Proxy({},{has(){throw reason}}),wrapped=NativeJitiInterop(target);let caught;
        \\try{wrapped.missing}catch(error){caught=error}if(caught!==reason)throw Error('raw trap reason');assertJitiCaptureEmpty();
        \\const data=JSON.parse('{"value":1}');if(NativeJitiJSON(data)!==data||data.default!==data)throw Error('JSON identity');
        \\const descriptor=Object.getOwnPropertyDescriptor(data,'default');if(descriptor.enumerable||descriptor.writable||descriptor.configurable||Object.keys(data).join()!=='value'||JSON.stringify(data)!=='{"value":1}')throw Error('JSON descriptor');
        \\const inherited=Object.create({default:'existing'});if(NativeJitiJSON(inherited)!==inherited||Object.hasOwn(inherited,'default'))throw Error('inherited JSON default');
        \\for(const value of[null,false,0,''])if(NativeJitiJSON(value)!==value)throw Error('falsy JSON primitive');
        \\for(const value of[true,1,'x']){caught=undefined;try{NativeJitiJSON(value)}catch(error){caught=error}if(!(caught instanceof TypeError))throw Error('truthy JSON primitive in operator');assertJitiCaptureEmpty()}
        \\const raw={default:0};if(NativeJitiDefault(raw,{default:true})!==0||NativeJitiDefault(raw,{default:false})!==raw||NativeJitiDefault(null,{default:true})!==null)throw Error('nullish default expression');
        \\export const passed=true;
    , "jiti-interop-raw-reasons-json.mjs");
    defer engine.freeValue(result);
}
/// Actual context/module/owned unique filename are composed by the future native
/// jiti constructor gate; no surrogate Node.Module is supplied here.
pub fn verifyRealCacheLifecycle(engine: *v.em.Engine, actual_context: c.JSValue, actual_module: c.JSValue, owned_filename: c.JSValue) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const opts = try s.get(actual_context, "opts");
    const old_interop = try s.get(opts, "interopDefault");
    const old_module_cache = try s.get(opts, "moduleCache");
    defer { s.set(opts, "interopDefault", old_interop) catch {}; s.set(opts, "moduleCache", old_module_cache) catch {}; }
    try s.set(opts, "interopDefault", c.pi_js_bool(engine.context, 0));
    try s.set(opts, "moduleCache", c.pi_js_bool(engine.context, 1));
    const parent = try s.own(try cache.forRequire(engine, actual_context));
    const native_cache = try s.get(try s.get(actual_context, "nativeRequire"), "cache");
    if (try js.hasKey(engine, parent, owned_filename) or try js.hasKey(engine, native_cache, owned_filename)) return error.ControlRequiresUnusedOwnedFilename;
    try cache.publishBeforeEval(engine, actual_context, parent, owned_filename, actual_module);
    const hit = try cache.lookup(engine, actual_context, parent, owned_filename); defer engine.freeValue(hit.value);
    try std.testing.expect(hit.hit);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, hit.value, try s.get(actual_module, "exports")));
    try cache.afterEvalFailure(engine, actual_context, owned_filename);
    try std.testing.expect(!try js.hasKey(engine, native_cache, owned_filename));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, try s.own(try js.getKey(engine, parent, owned_filename)), actual_module));
    try js.setKey(engine, native_cache, owned_filename, actual_module);
    try s.set(opts, "moduleCache", c.JS_NewInt32(engine.context, 0));
    try cache.afterNativeSuccess(engine, actual_context, owned_filename);
    try std.testing.expect(try js.hasKey(engine, native_cache, owned_filename));
    try s.set(opts, "moduleCache", c.pi_js_bool(engine.context, 0));
    try cache.afterNativeSuccess(engine, actual_context, owned_filename);
    try std.testing.expect(!try js.hasKey(engine, native_cache, owned_filename));
}
pub fn verifyActualImportMethod(engine: *v.em.Engine, actual_context: c.JSValue, actual_jiti_require: c.JSValue, actual_id: c.JSValue, accepted_default: c.JSValue) !void {
    const function = try @import("extensions/native_jiti_import.zig").create(engine, actual_context, actual_jiti_require); defer engine.freeValue(function);
    try std.testing.expect(c.JS_IsAsyncFunction(function) != 0);
    try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    const length = try js.get(engine, function, "length"); defer engine.freeValue(length);
    var arity: i32 = 0; if (c.JS_ToInt32(engine.context, &arity, length) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 2), arity);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const opts = try s.object(); try js.define(engine, opts, "default", c.pi_js_bool(engine.context, 1));
    const pending = try s.own(try js.call(engine, function, c.pi_js_undefined(), &.{ actual_id, opts }));
    const actual = try s.own(try engine.awaitValue(pending));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, accepted_default));
}
pub fn verifyNoGraphFrontendRetirement(engine: *v.em.Engine, actual_inputs: adapter.Inputs, actual_base: []const u8, actual_path: []const u8) !void {
    const before = adapter.retainedResources(engine);
    const first = try adapter.createSession(engine, actual_inputs);
    const pending = try adapter.start(engine, first, actual_base, actual_path, c.JS_NULL); defer engine.freeValue(pending);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(pending));
    const reason = engine.captured_exception orelse return error.ControlMissingRetiredReason;
    engine.captured_exception = null; engine.freeValue(reason);
    const after = adapter.retainedResources(engine);
    try std.testing.expectEqual(before.active_sessions, after.active_sessions);
    try std.testing.expectEqual(before.retired_tombstones + 1, after.retired_tombstones);
    try std.testing.expectEqual(before.bindings, after.bindings);
    try std.testing.expectEqual(before.private_entries, after.private_entries);
    try std.testing.expectError(error.InvalidExtensionImportSession, adapter.start(engine, first, actual_base, actual_path, c.pi_js_undefined()));
    const second = try adapter.createSession(engine, actual_inputs);
    try std.testing.expect(@intFromPtr(first) != @intFromPtr(second));
    try std.testing.expectError(error.InvalidExtensionImportSession, adapter.start(engine, first, actual_base, actual_path, c.pi_js_undefined()));
    const next = try adapter.start(engine, second, actual_base, actual_path, c.JS_NULL); defer engine.freeValue(next);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(next));
    const second_reason = engine.captured_exception orelse return error.ControlMissingSecondRetiredReason;
    engine.captured_exception = null; engine.freeValue(second_reason);
    const final = adapter.retainedResources(engine);
    try std.testing.expectEqual(before.bindings, final.bindings);
    try std.testing.expectEqual(before.retired_tombstones + 2, final.retired_tombstones);
}
fn freshAllocation(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try js.define(engine, roots[0], "original", c.JS_DupValue(engine.context, reason));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
}
pub fn verifyFreshTrapAllocation(engine: *v.em.Engine) !void {
    try installHooks(engine);
    const record = try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)); defer engine.freeValue(record);
    const raise = try @import("extensions/native_node_function.zig").create(engine, "raiseJitiNativeAllocation", 0, freshAllocation, &.{record}); defer engine.freeValue(raise);
    try install(engine, "raiseJitiNativeAllocation", raise);
    try install(engine, "jitiGuestCaught", c.pi_js_bool(engine.context, 0));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\const proxy=NativeJitiInterop({default:{get missing(){raiseJitiNativeAllocation()}}});
        \\try{proxy.missing}catch{jitiGuestCaught=true}
        \\throw Error('native trap allocation became ordinary');
    , "jiti-interop-trap-original-native-allocation.mjs"));
    const original = try js.get(engine, record, "original"); defer engine.freeValue(original);
    const reason = engine.captured_exception orelse return error.ControlMissingJitiNativeReason;
    try std.testing.expect(c.pi_js_native_allocation_error_generation(original) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    const caught = try js.global(engine, "jitiGuestCaught"); defer engine.freeValue(caught);
    try std.testing.expect(c.JS_ToBool(engine.context, caught) == 0);
    c.JS_ClearUncatchableError(engine.context, reason);
    engine.captured_exception = null;
    engine.freeValue(reason);
}
