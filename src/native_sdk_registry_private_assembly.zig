//! Private Root-intake assembly; full class and factory runtime parity remain incomplete.
//! Imports are the actual Root ordinary helpers; no opaque legacy AgentSession
//! prototype is inherited and no missing method gets an implementation here.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;

pub fn constructor(engine: *em.Engine, dependencies: c.JSValue, reference: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const staging = try scope.object();
    // These are actual bodies, not caller-overridden witnesses. Install the
    // qualified loadout after legacy query overlaps, and Root restore last.
    inline for (.{
        @import("extensions/native_sdk_session_public_values.zig"),   @import("extensions/native_sdk_session_queries.zig"),
        @import("extensions/native_sdk_session_utilities.zig"),       @import("extensions/native_sdk_session_events.zig"),
        @import("extensions/native_sdk_session_control.zig"),         @import("extensions/native_sdk_session_queue.zig"),
        @import("extensions/native_sdk_session_models.zig"),          @import("extensions/native_sdk_session_prepare.zig"),
        @import("extensions/native_sdk_session_prompt.zig"),          @import("extensions/native_sdk_session_prompt_images.zig"),
        @import("extensions/native_sdk_session_prompt_handlers.zig"), @import("extensions/native_sdk_session_post_run.zig"),
        @import("extensions/native_sdk_session_run.zig"),             @import("extensions/native_sdk_session_settled.zig"),
        @import("extensions/native_sdk_session_retry.zig"),           @import("extensions/native_sdk_session_statistics.zig"),
        @import("extensions/native_sdk_send_user.zig"),               @import("extensions/native_sdk_session_registry.zig"),
        @import("extensions/native_sdk_session_loadout.zig"),         @import("extensions/native_sdk_session_restore.zig"),
        @import("extensions/native_sdk_session_bindings.zig"),        @import("extensions/native_sdk_custom_message.zig"),
    }) |module| try module.install(engine, staging);
    try @import("extensions/native_sdk_session_compaction.zig").installHelpers(engine, staging);
    try @import("extensions/native_sdk_session_auto_compaction.zig").install(engine, staging);
    try @import("extensions/native_sdk_session_request_auth.zig").install(engine, staging, dependencies);
    try @import("extensions/native_sdk_session_hooks.zig").installWithDependencies(engine, staging, dependencies);
    try @import("extensions/native_sdk_check_compaction.zig").install(engine, staging, dependencies);
    try @import("extensions/native_sdk_session_boundaries.zig").install(engine, staging, dependencies);

    const prototype = try scope.object();
    const result = try scope.own(try @import("extensions/native_sdk_session_construct.zig").constructor(engine, prototype));
    const missing = try scope.array();
    const descriptors = try scope.get(reference, "descriptors");
    const count = try sdk.length(engine, descriptors);
    var missing_count: u32 = 0;
    for (0..count) |index| {
        const row = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, descriptors, @intCast(index))));
        const key = try scope.get(row, "key");
        if (scope.equal(key, try scope.text("constructor"))) continue;
        const atom = try js.atom(engine, key);
        defer c.JS_FreeAtom(engine.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const found = c.JS_GetOwnProperty(engine.context, &descriptor, staging, atom);
        if (found < 0) return js.capture(engine);
        if (found == 0) {
            try scope.index(missing, missing_count, key);
            missing_count += 1;
            continue;
        }
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        // Preserve actual installed descriptors. The strict gate below reports
        // wrong flags/arity/async/ownPrototype rather than correcting evidence.
        const flags = descriptor.flags | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
            (if (descriptor.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
        if (c.JS_DefineProperty(engine.context, prototype, atom, descriptor.value, descriptor.getter, descriptor.setter, flags) < 0) return js.capture(engine);
    }
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "nativeRegistryMissingMethods", missing);
    // Missing Source methods remain absent. completeSummarization's helper is
    // not a replacement for the still-required ordinary compaction/reload/etc.
    return c.JS_DupValue(engine.context, result);
}

fn runtime(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_sdk_extension_runtime.zig").create(engine, c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn providerCallbacks(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (argc != 6) return sdk.fail(engine, error.RequiredNativeFactoryProviderBindings);
    return @import("extensions/native_sdk_factory_provider_callbacks.zig").create(engine, args[0], args[1], args[2], args[3], args[4], args[5]) catch |err| sdk.fail(engine, err);
}
fn memoryStorage(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    // Fixture constructor adapter returns the real qualified native in-memory
    // storage protocol. This does not certify Source storage class metadata.
    const manager = try js.invoke(engine, roots[0], "inMemory", &.{});
    defer engine.freeValue(manager);
    return sdk.get(engine, (try sdk.state(engine, manager)).data, "storage");
}
fn promptUtility(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const first = if (argc > 0) args[0] else c.pi_js_undefined();
    return (switch (magic) {
        0 => @import("extensions/native_sdk_prompt_normalize.zig").normalize(engine, first),
        1 => @import("extensions/native_sdk_prompt_render.zig").buildSections(engine, first),
        2 => @import("extensions/native_sdk_prompt_render.zig").diffSections(engine, first, if (argc > 1) args[1] else c.pi_js_undefined()),
        else => unreachable,
    }) catch |err| sdk.fail(engine, err);
}
pub fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/native_crypto_random.zig").install(engine);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"native-registry-full-composition"});
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const namespace = try scope.object();
    try sdk.install(engine, namespace);
    try @import("extensions/native_agent_complete.zig").install(engine, namespace);
    const dependencies = try scope.object();
    try scope.put(dependencies, "SessionManager", try scope.get(namespace, "SessionManager"));
    try scope.put(dependencies, "NestedToolCallRunner", try scope.own(try @import("extensions/native_nested_tool_calls.zig").constructor(engine)));
    try scope.put(dependencies, "runToolCall", try scope.own(try @import("extensions/native_agent_single_tool.zig").create(engine)));
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, dependencies);
    try @import("extensions/native_sdk_chat_transport.zig").install(engine, dependencies);
    try scope.put(dependencies, "convertToLlm", try scope.own(try @import("extensions/native_sdk_messages.zig").create(engine)));
    try scope.put(dependencies, "normalizeToolResultImages", try scope.own(try @import("extensions/native_sdk_tool_result_images.zig").create(engine)));
    const reference_bytes = @embedFile("extensions/fixtures/sdk-session-prototype-original-5ab.json");
    const reference = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, reference_bytes, reference_bytes.len, "sdk-session-prototype-original-5ab.json")));
    try scope.put(namespace, "AgentSession", try scope.own(try constructor(engine, dependencies, reference)));
    try scope.put(namespace, "createExtensionRuntime", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, runtime, "createExtensionRuntime", 0))));
    try scope.put(namespace, "createFactoryProviderCallbacks", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, providerCallbacks, "createFactoryProviderCallbacks", 6))));
    try scope.put(namespace, "applyToolModifiers", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, @import("extensions/native_sdk_tool_modifiers.zig").callback, "applyToolModifiers", 2))));
    try scope.put(namespace, "InMemorySettingsStorage", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "InMemorySettingsStorage", 0, memoryStorage, &.{try scope.get(namespace, "SettingsManager")})));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "registryNative", namespace);
    try scope.put(global, "registryNativePrototypeSource", reference);
    try scope.put(global, "registryNativeStream", try scope.get(dependencies, "streamSimple"));
    try scope.put(global, "registryCacheWarmer", try scope.own(try @import("extensions/native_cache_warmer.zig").createBindings(engine)));
    inline for (.{ "normalizeLoadoutOptions", "buildLoadoutSections", "diffLoadoutSections" }, 0..) |name, index| {
        try scope.put(global, name, try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, promptUtility, name, if (index == 2) 2 else 1, @intCast(index)))));
    }
    const prepared = engine.evalModule(@embedFile("extensions/fixtures/sdk-registry-private-factory.input.txt"), "native-registry-private-fixture-factory.mjs") catch |err| {
        std.debug.print("Private registry assembly missing dependency: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(prepared);
}
