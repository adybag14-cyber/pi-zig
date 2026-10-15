//! New production-constructor qualification entrypoint. Positive execution must
//! receive real AI/provider and ModelRuntime/resource/config components; no
//! fabricated Models, no empty provider registry, and no legacy session object.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const production = @import("extensions/native_sdk_session_production.zig");
const c = em.c;

/// Root/central AI assembly supplies these actual components after its own
/// bootstrap. The production constructor uses all original initialization
/// phases and real method bodies; this function replaces no collaborators.
pub fn constructActual(engine: *em.Engine, ai: c.JSValue, compat: c.JSValue, sdk_namespace: c.JSValue, shared_ai: c.JSValue, config: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.own(try production.constructor(engine, .{
        .ai = ai,
        .compat = compat,
        .sdk_namespace = sdk_namespace,
        .shared_ai = shared_ai,
        .install_session_exports = @import("extensions/native_sdk_session_platform_composition.zig").install,
    }));
    var inputs = [_]c.JSValue{config};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, inputs.len, &inputs));
}

/// Comparator against the unchanged genuine Source166 inventory. This does not
/// correct descriptors or manufacture absent methods to satisfy the reference.
pub fn verifyActualPrototype(engine: *em.Engine, constructor: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(constructor, "prototype");
    const parent = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, prototype)));
    const object_prototype = try scope.get(try scope.global("Object"), "prototype");
    if (!scope.equal(parent, object_prototype)) return error.OrdinaryAgentSessionInheritedLegacyPrototype;
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "productionConstructorProbe", constructor);
    const bytes = @embedFile("extensions/fixtures/sdk-session-prototype-original-5ab.json");
    try scope.put(global, "productionConstructorSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "actual-source166.json"))));
    const verified = try engine.evalModule(
        \\const p=productionConstructorProbe.prototype,describe=f=>f===undefined?undefined:({name:f.name,length:f.length,async:Object.getPrototypeOf(f)===Object.getPrototypeOf(async()=>{}),ownPrototype:Object.hasOwn(f,'prototype')});const actual=Reflect.ownKeys(p).map(key=>{const d=Object.getOwnPropertyDescriptor(p,key);return{key,kind:'value'in d?'data':'accessor',enumerable:d.enumerable,configurable:d.configurable,...('writable'in d?{writable:d.writable}:{}),...('value'in d?{valueType:typeof d.value,function:typeof d.value==='function'?describe(d.value):undefined}:{get:describe(d.get),set:describe(d.set)})}});if(JSON.stringify(actual)!==JSON.stringify(productionConstructorSource.descriptors))throw Error(JSON.stringify({actual,expected:productionConstructorSource.descriptors}));delete globalThis.productionConstructorProbe;delete globalThis.productionConstructorSource;export const complete=true;
    , "actual-production-constructor-source166.mjs");
    engine.freeValue(verified);
}

pub fn verifyOrdinaryInstance(engine: *em.Engine, constructor: c.JSValue, session: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, session)));
    if (!scope.equal(prototype, try scope.get(constructor, "prototype"))) return error.ActualOrdinarySessionConstructorIdentityMismatch;
    if (engine.native_sdk_class != 0 and c.JS_GetOpaque(session, engine.native_sdk_class) != null) return error.OpaqueLegacyAgentSessionInProduction;
    const keys = try scope.own(try js.objectMethod(engine, "keys", session));
    if (!scope.equal(try scope.get(keys, "length"), c.JS_NewInt32(engine.context, 66))) return error.ActualOrdinarySessionDeclarationsMissing;
    if (!c.JS_IsFunction(engine.context, try scope.get(session, "_handleAgentEvent"))) return error.ActualOrdinaryHandleAgentEventMissing;
}

test "native production constructor rejects absent actual AI namespaces without creating placeholders" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try std.testing.expectError(error.RequiredActualNativeNamespace, production.validateInputs(engine, .{
        .ai = c.pi_js_undefined(),
        .compat = c.pi_js_undefined(),
        .sdk_namespace = c.pi_js_undefined(),
        .shared_ai = c.pi_js_undefined(),
        .install_session_exports = null,
    }));
}
test "native production constructor declaration order is actual Source166 without runtime oracle mutation" {
    const bytes = @embedFile("extensions/fixtures/sdk-session-prototype-original-5ab.json");
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    const rows = parsed.value.object.get("descriptors").?.array.items;
    const names = @import("extensions/native_sdk_session_declaration_order.zig").names;
    try std.testing.expectEqual(@as(usize, 166), rows.len);
    try std.testing.expectEqual(rows.len - 1, names.len);
    for (names, rows[1..]) |name, row| try std.testing.expectEqualStrings(name, row.object.get("key").?.string);
}
