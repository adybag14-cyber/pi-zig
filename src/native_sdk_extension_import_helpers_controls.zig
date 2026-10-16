//! Prepared controls over actual namespaces, source expectations and the reviewed
//! queued import binding. No jiti facade or dummy registry is constructed.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const lazy = @import("extensions/native_sdk_extension_lazy_imports.zig");
const c = em.c;
fn install(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
pub fn verifyAliasCache(engine: *em.Engine, actual_aliases: c.JSValue, accepted_source_aliases: c.JSValue) !void {
    const first = try js.call(engine, actual_aliases, c.pi_js_undefined(), &.{}); defer engine.freeValue(first);
    const second = try js.call(engine, actual_aliases, c.pi_js_undefined(), &.{}); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    try install(engine, "ActualExtensionAliases", first);
    try install(engine, "SourceExtensionAliases", accepted_source_aliases);
    const result = try engine.evalModule(
        \\const actual=ActualExtensionAliases,source=SourceExtensionAliases;
        \\if(Object.keys(actual).join()!==Object.keys(source).join()||Object.keys(actual).length!==20)throw Error('actual alias declaration order');
        \\for(const key of Object.keys(source))if(actual[key]!==source[key])throw Error(`physical alias ${key}`);
        \\for(const key of Object.keys(actual)){const alias=key.replace('@earendil-works/','@mariozechner/').replace(/^typebox/,'@sinclair/typebox');if(alias in actual&&actual[key]!==actual[alias])throw Error('alias identity')}
        \\export const passed=true;
    , "extension-aliases-real-source-cache.mjs");
    defer engine.freeValue(result);
}
/// The fresh actual getter has not yet cached aliases. Mutate only its actual
/// private loader metadata, restore its original descriptor before returning.
pub fn verifyAliasRawReason(engine: *em.Engine, fresh_actual_aliases: c.JSValue, actual_import_meta: c.JSValue) !void {
    try install(engine, "ActualGetExtensionAliases", fresh_actual_aliases);
    try install(engine, "ActualLoaderImportMeta", actual_import_meta);
    const result = try engine.evalModule(
        \\const meta=ActualLoaderImportMeta,descriptor=Object.getOwnPropertyDescriptor(meta,'url'),reason={meta:true};let gets=0,caught;
        \\Object.defineProperty(meta,'url',{configurable:true,get(){gets++;throw reason}});
        \\try{try{ActualGetExtensionAliases()}catch(error){caught=error}}finally{Object.defineProperty(meta,'url',descriptor)}
        \\if(caught!==reason||gets!==1)throw Error('actual aliases raw metadata reason');
        \\export const passed=true;
    , "extension-aliases-raw-metadata-reason.mjs");
    defer engine.freeValue(result);
}
/// Complete the real SDK namespace after import() returns but before its queued
/// job. This detects the unsupported synchronous JS_LoadModule substitution.
pub fn verifyQueuedVirtualCompletion(engine: *em.Engine, inputs: lazy.Inputs, actual_completed_sdk: c.JSValue) !void {
    if (engine.native_module_names.contains(inputs.virtual_names.coding_agent)) return error.ControlRequiresUnpublishedActualSdk;
    const helpers = try lazy.create(engine, inputs); defer engine.freeValue(helpers);
    const importing = try js.get(engine, helpers, "importVirtualModule"); defer engine.freeValue(importing);
    const pending = try js.call(engine, importing, c.pi_js_undefined(), &.{}); defer engine.freeValue(pending);
    try std.testing.expect(c.JS_PromiseState(engine.context, pending) == c.JS_PROMISE_PENDING);
    try std.testing.expect(engine.captured_exception == null);
    try engine.registerValueModule(inputs.virtual_names.coding_agent, actual_completed_sdk);
    const namespace = try engine.awaitValue(pending); defer engine.freeValue(namespace);
    const modules = try js.get(engine, namespace, "VIRTUAL_MODULES"); defer engine.freeValue(modules);
    const sdk = try js.get(engine, modules, "@earendil-works/pi-coding-agent"); defer engine.freeValue(sdk);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, sdk, actual_completed_sdk));
    const again = try js.call(engine, importing, c.pi_js_undefined(), &.{}); defer engine.freeValue(again);
    const same_namespace = try engine.awaitValue(again); defer engine.freeValue(same_namespace);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, namespace, same_namespace));
    const same_modules = try js.get(engine, same_namespace, "VIRTUAL_MODULES"); defer engine.freeValue(same_modules);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, modules, same_modules));
}
pub fn verifyCreateJitiPromiseCache(engine: *em.Engine, actual_helpers: c.JSValue, actual_create_jiti: c.JSValue) !void {
    const getter = try js.get(engine, actual_helpers, "getCreateJiti"); defer engine.freeValue(getter);
    const first = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(first);
    const second = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    const factory = try engine.awaitValue(first); defer engine.freeValue(factory);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, factory, actual_create_jiti));
    const third = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(third);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, third));
}
pub fn verifyMissingJitiRetainsRejection(engine: *em.Engine, inputs: lazy.Inputs) !void {
    const selected = if (inputs.uses_embedded_modules) inputs.static_jiti_namespace else inputs.lazy_jiti_namespace;
    if (engine.native_module_names.contains(selected)) return error.ControlRequiresMissingActualJiti;
    const helpers = try lazy.create(engine, inputs); defer engine.freeValue(helpers);
    const getter = try js.get(engine, helpers, "getCreateJiti"); defer engine.freeValue(getter);
    const first = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(first);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(first));
    const original = engine.captured_exception orelse return error.ControlMissingJitiReason;
    engine.captured_exception = null;
    defer engine.freeValue(original);
    const second = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(second));
    const repeated = engine.captured_exception orelse return error.ControlMissingRepeatedJitiReason;
    engine.captured_exception = null;
    defer engine.freeValue(repeated);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, repeated));
}
pub fn verifyResolverReplacementGuard(engine: *em.Engine, actual_physical_filename: []const u8) !void {
    const resolver = try @import("extensions/native_sdk_extension_alias_resolver.zig").create(engine, actual_physical_filename); defer engine.freeValue(resolver);
    const original = engine.source_loader;
    defer engine.source_loader = original;
    engine.source_loader = null;
    const specifier = try engine.checked(c.JS_NewString(engine.context, "@earendil-works/pi-ai/compat")); defer engine.freeValue(specifier);
    try std.testing.expectError(error.JavaScriptException, js.call(engine, resolver, c.pi_js_undefined(), &.{specifier}));
    const reason = engine.captured_exception orelse return error.ControlMissingResolverReplacementReason;
    engine.captured_exception = null;
    defer engine.freeValue(reason);
    const message = try js.get(engine, reason, "message"); defer engine.freeValue(message);
    const text = try engine.toString(message); defer engine.gpa.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "ActualAliasSourceLoaderChanged") != null);
}
